@echo off
echo don't enter an export password when prompted
echo.
cd "C:\Users\Ryan Partington\OneDrive\cert maker"
"C:\Program Files\OpenSSL-Win64\bin\openssl" pkcs12 -export -out main.pfx -inkey private.key -in certificate.crt -certfile ca_bundle.crt
echo.
echo if RDC server, double click the pfx file and install it in LOCAL MACHINE, then try and install via normal way
pause