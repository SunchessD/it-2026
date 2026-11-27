@echo off
setlocal DisableDelayedExpansion
pushd "%~dp0" || exit /b 1
set "demo_exit=1"
set "demo_mode=demo"
if "%~1"=="" goto mode_ready
if /i "%~1"=="demo" goto mode_ready
if /i "%~1"=="test" (
    set "demo_mode=test"
    goto mode_ready
)
echo Usage: run-windows.cmd [demo or test]
goto finish

:mode_ready
set "PYTHONUTF8=1"
if not defined REDIS_DEMO_PORT set "REDIS_DEMO_PORT=6379"
if exist ".venv\Scripts\python.exe" goto python_ready
py -3 -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if errorlevel 1 goto try_python
py -3 -m venv .venv
if errorlevel 1 goto finish
goto python_ready

:try_python
python -c "import sys; sys.exit(sys.version_info < (3, 10))" >nul 2>&1
if errorlevel 1 (
    echo Python 3.10 or newer is required. Install Python and reopen this window.
    goto finish
)
python -m venv .venv
if errorlevel 1 goto finish

:python_ready
".venv\Scripts\python.exe" -c "import sys; sys.exit(sys.version_info < (3, 10))"
if errorlevel 1 (
    echo The local .venv is not usable. See README.md.
    goto finish
)
".venv\Scripts\python.exe" -c "import os,sys; p=os.environ['REDIS_DEMO_PORT']; sys.exit(not (p.isascii() and p.isdigit() and 1 <= int(p) <= 65535))"
if errorlevel 1 (
    echo REDIS_DEMO_PORT must be a number from 1 to 65535.
    goto finish
)
".venv\Scripts\python.exe" -c "import redis,sys; sys.exit(redis.__version__ != '6.4.0')" >nul 2>&1
if not errorlevel 1 goto docker_ready
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r requirements.txt
if errorlevel 1 goto finish

:docker_ready
docker compose version >nul 2>&1
if errorlevel 1 (
    echo Docker Desktop with Docker Compose is required. See README.md.
    goto finish
)
docker info >nul 2>&1
if errorlevel 1 (
    echo Start Docker Desktop, wait for the engine, and run this file again.
    goto finish
)
docker info --format "{{.OSType}}" | findstr /x /c:"linux" >nul
if errorlevel 1 (
    echo Switch Docker Desktop to Linux containers and run this file again.
    goto finish
)
docker compose up -d --wait --wait-timeout 60 redis
if errorlevel 1 (
    echo Redis did not start. Check the Docker message above and README.md.
    goto finish
)
docker compose exec -T redis redis-cli ping
if errorlevel 1 goto finish
set "REDIS_URL=redis://127.0.0.1:%REDIS_DEMO_PORT%/0"
echo.
if /i "%demo_mode%"=="test" goto run_tests
".venv\Scripts\python.exe" demo.py --redis-url "%REDIS_URL%"
set "demo_exit=%errorlevel%"
goto finish

:run_tests
".venv\Scripts\python.exe" -m unittest -v test_demo.py
set "demo_exit=%errorlevel%"

:finish
echo.
if not "%demo_exit%"=="0" echo The run failed. See the message above.
echo To stop the demo container later, use: docker compose down
if "%~1"=="" pause
popd
endlocal & exit /b %demo_exit%
