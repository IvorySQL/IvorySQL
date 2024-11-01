@echo off
rem install script for x64
call install.bat %* || goto exit
if exist ..\..\..\configure cd ..\..\..
if exist ..\..\..\..\configure cd ..\..\..\..
copy c:\buildenv\deps\lib_x64\gettext\libintl.dll %1\bin
copy c:\buildenv\deps\lib_x64\libiconv\libiconv.dll %1\bin
copy c:\buildenv\deps\lib_x64\libxml2\bin\libxml2.dll %1\bin
copy c:\buildenv\deps\lib_x64\libxslt\lib\libxslt.dll %1\bin
copy c:\buildenv\deps\lib_x64\zlib\zlib1.dll %1\bin
copy c:\buildenv\deps\lib_x64\openssl\bin\libeay32.dll %1\bin
copy c:\buildenv\deps\lib_x64\openssl\bin\ssleay32.dll %1\bin
cd %~dp0 
:exit
exit /b %errorlevel%

