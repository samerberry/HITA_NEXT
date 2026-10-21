@echo off
chcp 65001 >nul
echo ========================================
echo   HitaNEXT 编译并安装到鸿蒙设备
echo ========================================

if not defined DEVECO_HOME set "DEVECO_HOME=%ProgramFiles%\Huawei\DevEco Studio"
if not exist "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat" set "DEVECO_HOME=D:\deveco studio\Deveco studio"
if not exist "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat" (
    echo [错误] 未找到 DevEco Studio，请设置 DEVECO_HOME 后重试。
    pause
    exit /b 1
)
set "HDC_PATH=%DEVECO_HOME%\sdk\default\openharmony\toolchains\hdc.exe"
set "NODE_HOME=%DEVECO_HOME%\tools\node"
set "DEVECO_SDK_HOME=%DEVECO_HOME%\sdk"
set "JAVA_HOME=%DEVECO_HOME%\jbr"
set "PATH=%NODE_HOME%;%JAVA_HOME%\bin;%PATH%"

cd /d "%~dp0"

echo [1/3] 编译 HAP...
call "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon
if errorlevel 1 (
    echo [错误] 编译失败，请检查报错！
    pause
    exit /b 1
)

echo.
if not exist "%~dp0entry\build\default\outputs\default\entry-default-signed.hap" (
    echo [提示] 当前只生成了 unsigned HAP：
    echo        %~dp0entry\build\default\outputs\default\entry-default-unsigned.hap
    echo [提示] 请确认 DevEco Studio 打开的项目目录是本脚本所在目录，
    echo        并确认 build-profile.json5 中 default 产品关联了有效签名配置。
    pause
    exit /b 0
)

echo [2/3] 检查连接设备...
"%HDC_PATH%" list targets
if errorlevel 1 (
    echo [错误] 未检测到鸿蒙设备，请确认手机已开启 USB 调试并允许连接！
    pause
    exit /b 1
)

echo.
echo [3/3] 安装到真机...
"%HDC_PATH%" install -r "%~dp0entry\build\default\outputs\default\entry-default-signed.hap"
if errorlevel 1 (
    echo [错误] 安装失败！
    pause
    exit /b 1
)

echo.
echo [提示] 正在启动应用（请先点亮并解锁手机屏幕）...
"%HDC_PATH%" shell power-shell wakeup
"%HDC_PATH%" shell aa start -a EntryAbility -b cn.berry.hitanext

echo.
echo [完成] 应用已安装成功！如果手机处于锁屏状态，请解锁屏幕后在桌面点击 HITA 图标打开。
pause
