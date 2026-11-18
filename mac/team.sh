# Підключається скриптами збірки: визначає Team ID для підпису.
# Пріоритет: змінна EB3A_TEAM → файл mac/team.local → помилка з підказкою.
if [ -z "$EB3A_TEAM" ] && [ -f "$ROOT/mac/team.local" ]; then
  EB3A_TEAM=$(tr -d ' \n' < "$ROOT/mac/team.local")
fi
if [ -z "$EB3A_TEAM" ]; then
  echo "Вкажи свій Apple Team ID: echo XXXXXXXXXX > mac/team.local (Xcode → Settings → Accounts → Team)" >&2
  exit 1
fi
export EB3A_TEAM
