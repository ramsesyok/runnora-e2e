// contract-check は、契約テストの期待値とモックの戻り値が同じファイルを指していることを検査する。
//
//	go run ./tools/contract-check -root .
//
// 契約 suite (runbooks/contract/*.suite.yml) はケースごとに include ステップを並べ、
// vars.case (ケース JSON) と vars.expected (期待本文) を渡す。runn はこの組合せの正しさを
// 知らないため、各ステップについて次をすべて満たすことを確かめる。
//
//  1. vars.case と vars.expected がどちらも json:// で指定されている
//  2. ケース JSON の expect.mockCase が mock/mock-cases.yaml に存在する
//  3. そのモックケースの bodyFile が vars.expected と同じファイル (fixtures/responses/ 基準)
//  4. そのモックケースの応答ステータスがケース JSON の expect.status と同じ
//  5. 1 つのモックケースを複数の契約ケースが使っていない
//  6. suite に loop が無い (runn の loop は最後の回の失敗しか報告しないため)
//
// 契約ケースから参照されていない fallback 以外のモックケースは参考として一覧表示する。
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

const responsesRoot = "fixtures/responses"

type mockCase struct {
	ID       string `yaml:"id"`
	Fallback bool   `yaml:"fallback"`
	Response struct {
		Status   int    `yaml:"status"`
		BodyFile string `yaml:"bodyFile"`
	} `yaml:"response"`
}

type suite struct {
	Steps yaml.Node `yaml:"steps"`
}

type step struct {
	Loop    any `yaml:"loop"`
	Include *struct {
		Vars struct {
			Case     string `yaml:"case"`
			Expected string `yaml:"expected"`
		} `yaml:"vars"`
	} `yaml:"include"`
}

type contractCase struct {
	Name   string `json:"name"`
	Expect struct {
		Status   int    `json:"status"`
		MockCase string `json:"mockCase"`
	} `json:"expect"`
}

func main() {
	root := flag.String("root", ".", "runnora-e2e のルート")
	flag.Parse()
	if abs, err := filepath.Abs(*root); err == nil {
		*root = abs
	}

	var errs []string
	fail := func(format string, a ...any) { errs = append(errs, fmt.Sprintf(format, a...)) }

	var mocks struct {
		Cases []mockCase `yaml:"cases"`
	}
	if err := readYAML(filepath.Join(*root, "mock/mock-cases.yaml"), &mocks); err != nil {
		exit(err)
	}
	byID := map[string]mockCase{}
	for _, c := range mocks.Cases {
		byID[c.ID] = c
	}

	suites, err := filepath.Glob(filepath.Join(*root, "runbooks/contract/*.suite.yml"))
	if err != nil {
		exit(err)
	}
	usedBy := map[string]string{}
	total := 0
	for _, path := range suites {
		name := filepath.Base(path)
		var s suite
		if err := readYAML(path, &s); err != nil {
			exit(err)
		}
		// steps はステップ名の順序を保つため Node のまま読む (key, value が交互に並ぶ)
		for i := 0; i+1 < len(s.Steps.Content); i += 2 {
			stepName := s.Steps.Content[i].Value
			var st step
			if err := s.Steps.Content[i+1].Decode(&st); err != nil {
				exit(err)
			}
			where := fmt.Sprintf("%s steps.%s", name, stepName)
			if st.Loop != nil {
				fail("%s: loop は使わない (途中の回の失敗が報告されない)", where)
			}
			if st.Include == nil {
				continue
			}
			v := st.Include.Vars
			if !strings.HasPrefix(v.Case, "json://") || !strings.HasPrefix(v.Expected, "json://") {
				fail("%s: vars.case と vars.expected は json:// で指定する", where)
				continue
			}
			total++
			var c contractCase
			if err := readJSON(resolve(path, v.Case), &c); err != nil {
				fail("%s: %v", where, err)
				continue
			}
			m, ok := byID[c.Expect.MockCase]
			if !ok {
				fail("%s: expect.mockCase %q が mock/mock-cases.yaml にない", where, c.Expect.MockCase)
				continue
			}
			if prev, dup := usedBy[m.ID]; dup {
				fail("%s: モックケース %s は %s でも使われている", where, m.ID, prev)
			}
			usedBy[m.ID] = where

			want := filepath.Clean(filepath.Join(*root, responsesRoot, m.Response.BodyFile))
			got := filepath.Clean(resolve(path, v.Expected))
			if !strings.EqualFold(want, got) {
				fail("%s: vars.expected が %s を指している (モック %s の bodyFile は %s)", where, rel(*root, got), m.ID, rel(*root, want))
			}
			if _, err := os.Stat(got); err != nil {
				fail("%s: 期待本文ファイルがない: %s", where, rel(*root, got))
			}
			if m.Response.Status != c.Expect.Status {
				fail("%s: expect.status %d とモック %s のステータス %d が違う", where, c.Expect.Status, m.ID, m.Response.Status)
			}
		}
	}

	var unused []string
	for _, c := range mocks.Cases {
		if _, ok := usedBy[c.ID]; !ok && !c.Fallback {
			unused = append(unused, c.ID)
		}
	}
	sort.Strings(unused)

	fmt.Printf("契約ケース %d 件 / モックケース %d 件 (うち契約ケースと対応 %d 件)\n", total, len(mocks.Cases), len(usedBy))
	if len(unused) > 0 {
		fmt.Printf("参考: 契約ケースから参照されていないモックケース: %s\n", strings.Join(unused, ", "))
	}
	if len(errs) > 0 {
		for _, e := range errs {
			fmt.Fprintln(os.Stderr, "NG:", e)
		}
		os.Exit(1)
	}
	fmt.Println("OK: 契約ケースの期待本文とモックの戻り値は同じファイルを参照している")
}

// resolve は suite に書かれた json://<相対パス> を絶対パスにする。
// runn は include 先 template の位置で解決するが、template は suite と同じ場所に置く前提。
func resolve(suitePath, ref string) string {
	return filepath.Join(filepath.Dir(suitePath), filepath.FromSlash(strings.TrimPrefix(ref, "json://")))
}

func rel(root, path string) string {
	abs, _ := filepath.Abs(root)
	if r, err := filepath.Rel(abs, path); err == nil {
		return filepath.ToSlash(r)
	}
	return path
}

func readYAML(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return yaml.Unmarshal(data, v)
}

func readJSON(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

func exit(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(2)
}
