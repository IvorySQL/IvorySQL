@echo off

if "%1" equ "win32" (
	set up_x64=
	set openssl_x64=
	goto doit
)
if "%1" equ "x64" (
	set up_x64=_x64
	set openssl_x64=-x64
	goto doit
)
goto help


:doit
if "%2" equ "" goto help

>setenv.bat		echo @echo off
>>setenv.bat	echo if "%%UP_BUILDENV%%" neq "" goto exit
>>setenv.bat	echo set UP_BUILDENV=%2
>>setenv.bat	echo set PATH=%%UP_BUILDENV%%\deps\perl520%up_x64%\bin;%%PATH%%
>>setenv.bat	echo set PATH=%%UP_BUILDENV%%\deps\python27%up_x64%;%%PATH%%
>>setenv.bat	echo set PATH=%%UP_BUILDENV%%\deps\tcl85%up_x64%\bin;%%PATH%%
>>setenv.bat	echo set PYTHONHOME=%%UP_BUILDENV%%\deps\python27%up_x64%
>>setenv.bat	echo set PYTHONPATH=%%UP_BUILDENV%%\deps\python27%up_x64%\Lib
>>setenv.bat	echo :exit
>>setenv.bat	echo.

>config.pl		echo # config for %1
>>config.pl		echo $config-^>{tcl} = '%2\deps\tcl85%up_x64%';
>>config.pl		echo $config-^>{perl} = '%2\deps\perl520%up_x64%';
>>config.pl		echo $config-^>{python} = '%2\deps\python27%up_x64%';
>>config.pl		echo $config-^>{nls} = '%2\deps\lib%up_x64%\gettext';
>>config.pl		echo $config-^>{openssl} = '%2\deps\lib%up_x64%\openssl';
>>config.pl		echo $config-^>{uuid} = '%2\deps\lib%up_x64%\uuid';
>>config.pl		echo $config-^>{xml} = '%2\deps\lib%up_x64%\libxml2';
>>config.pl		echo $config-^>{xslt} = '%2\deps\lib%up_x64%\libxslt';
>>config.pl		echo $config-^>{iconv} = '%2\deps\lib%up_x64%\libiconv';
>>config.pl		echo $config-^>{zlib} = '%2\deps\lib%up_x64%\zlib';

>buildenv.pl	echo # set environments
>>buildenv.pl	echo $ENV{PATH} = 
>>buildenv.pl	echo    '%2\deps\tools\usr\bin;'.
>>buildenv.pl	echo    '%2\deps\python27%up_x64%;'.
>>buildenv.pl	echo    '%2\deps\tcl85%up_x64%\bin;'.
>>buildenv.pl	echo    '%2\deps\lib%up_x64%\gettext;'.
>>buildenv.pl	echo    '%2\deps\lib%up_x64%\openssl\bin;'.
>>buildenv.pl	echo    '%2\deps\lib%up_x64%\libxml2\bin;'.
>>buildenv.pl	echo    '%2\deps\lib%up_x64%\libxslt\lib;'.
>>buildenv.pl	echo    '%2\deps\lib%up_x64%\libiconv;'.
>>buildenv.pl	echo    '%2\deps\lib%up_x64%\zlib;'.$ENV{PATH};
>>buildenv.pl	echo #$ENV{CONFIG} = "Debug";
>>buildenv.pl	echo $ENV{DOCROOT} = '%2\deps\docbook';
>>buildenv.pl	echo $ENV{PERL5LIB} = $ENV{PERL5LIB}.';%2\deps\IPC-Run-0.94\lib';

>instal.bat		echo @echo off
>>instal.bat	echo rem install script for %1
>>instal.bat	echo call install.bat %%* ^|^| goto exit
>>instal.bat	echo if exist ..\..\..\configure cd ..\..\..
>>instal.bat	echo if exist ..\..\..\..\configure cd ..\..\..\..
>>instal.bat	echo copy %2\deps\lib%up_x64%\gettext\libintl.dll %%1\bin
>>instal.bat	echo copy %2\deps\lib%up_x64%\libiconv\libiconv.dll %%1\bin
>>instal.bat	echo copy %2\deps\lib%up_x64%\libxml2\bin\libxml2.dll %%1\bin
>>instal.bat	echo copy %2\deps\lib%up_x64%\libxslt\lib\libxslt.dll %%1\bin
>>instal.bat	echo copy %2\deps\lib%up_x64%\zlib\zlib1.dll %%1\bin
>>instal.bat	echo copy %2\deps\lib%up_x64%\openssl\bin\libcrypto-3%openssl_x64%.dll %%1\bin
>>instal.bat	echo copy %2\deps\lib%up_x64%\openssl\bin\libssl-3%openssl_x64%.dll %%1\bin
>>instal.bat	echo cd %%~dp0 
>>instal.bat	echo :exit
>>instal.bat	echo exit /b %%errorlevel%%
>>instal.bat	echo.

set up_x64=
goto exit

:help
echo config ^<win32^|x64^> ^<path_to_buildenv^>

:exit

