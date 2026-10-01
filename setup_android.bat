@echo off
flutter create . --platforms=android --project-name=audytor_app --org=pl.audytor
if errorlevel 1 exit /b 1
powershell -NoProfile -Command "$p='android/app/build.gradle.kts'; if(Test-Path $p){$s=Get-Content $p -Raw; $s=$s.Replace('minSdk = flutter.minSdkVersion','minSdk = 24'); Set-Content $p $s}"
if errorlevel 1 exit /b 1
flutter pub get
if errorlevel 1 exit /b 1
flutter run
