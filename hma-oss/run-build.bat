@echo off
cd /d "%~dp0"
set JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=%~dp0.buildtools\truststore.jks -Djavax.net.ssl.trustStorePassword=changeit
call gradlew.bat --console=plain -Dorg.gradle.internal.http.connectionTimeout=120000 -Dorg.gradle.internal.http.socketTimeout=180000 %*
