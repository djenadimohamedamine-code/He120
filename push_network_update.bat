@echo off
cd /d %~dp0
echo --- PUSH MISE A JOUR RESEAU ---
git add lib/main.dart
git commit -m "Update proxyHost IP for TriCaster and Modem network"
git push
echo.
echo ✅ C'est pousse sur GitHub ! Le build automatique (Actions) devrait demarrer.
pause
