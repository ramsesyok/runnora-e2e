param(
    [switch]$UseCachedJars,
    [string]$MavenRepository = (Join-Path $env:USERPROFILE '.m2/repository')
)
$ErrorActionPreference = 'Stop'
$trialRoot = Split-Path $PSScriptRoot -Parent
$serverRoot = Join-Path $trialRoot 'server'
$targetDir = Join-Path $serverRoot 'target'
New-Item -ItemType Directory -Force $targetDir | Out-Null
if (-not $UseCachedJars) {
    & mvn --batch-mode --no-transfer-progress -f (Join-Path $serverRoot 'pom.xml') package -DskipTests
    if ($LASTEXITCODE -ne 0) { throw 'Spring Boot server build failed' }
    return
}
# Offline reproduction using the exact dependencies already cached on this host.
$coordinates = @(
    'org/springframework/boot/spring-boot/2.7.15/spring-boot-2.7.15.jar',
    'org/springframework/boot/spring-boot-autoconfigure/2.7.15/spring-boot-autoconfigure-2.7.15.jar',
    'jakarta/annotation/jakarta.annotation-api/1.3.5/jakarta.annotation-api-1.3.5.jar',
    'org/slf4j/slf4j-api/1.7.36/slf4j-api-1.7.36.jar',
    'org/slf4j/jul-to-slf4j/1.7.36/jul-to-slf4j-1.7.36.jar',
    'ch/qos/logback/logback-classic/1.2.12/logback-classic-1.2.12.jar',
    'ch/qos/logback/logback-core/1.2.12/logback-core-1.2.12.jar',
    'org/yaml/snakeyaml/1.30/snakeyaml-1.30.jar'
)
foreach ($artifact in @('spring-aop','spring-beans','spring-context','spring-core','spring-expression','spring-jcl','spring-web','spring-webmvc')) {
    $coordinates += "org/springframework/$artifact/5.3.29/$artifact-5.3.29.jar"
}
foreach ($artifact in @('tomcat-embed-core','tomcat-embed-el','tomcat-embed-websocket')) {
    $coordinates += "org/apache/tomcat/embed/$artifact/9.0.79/$artifact-9.0.79.jar"
}
foreach ($artifact in @('jackson-annotations','jackson-core','jackson-databind')) {
    $coordinates += "com/fasterxml/jackson/core/$artifact/2.13.5/$artifact-2.13.5.jar"
}
foreach ($artifact in @('jackson-datatype-jdk8','jackson-datatype-jsr310')) {
    $coordinates += "com/fasterxml/jackson/datatype/$artifact/2.13.5/$artifact-2.13.5.jar"
}
$coordinates += 'com/fasterxml/jackson/module/jackson-module-parameter-names/2.13.5/jackson-module-parameter-names-2.13.5.jar'
$jars = foreach ($coordinate in $coordinates) {
    $jarPath = Join-Path $MavenRepository $coordinate
    if (-not (Test-Path -LiteralPath $jarPath)) { throw "Cached dependency not found: $jarPath" }
    $jarPath
}
$classes = Join-Path $targetDir 'classes'
New-Item -ItemType Directory -Force $classes | Out-Null
$javaPath = (Get-Command java -ErrorAction Stop).Source
$javacPath = Join-Path (Split-Path $javaPath -Parent) 'javac.exe'
$classPath = $jars -join [IO.Path]::PathSeparator
& $javacPath -encoding UTF-8 -cp $classPath -d $classes (Join-Path $serverRoot 'src/main/java/trial/MultipartApplication.java')
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
[IO.File]::WriteAllText((Join-Path $targetDir 'classpath.txt'), ($classes + [IO.Path]::PathSeparator + $classPath))
