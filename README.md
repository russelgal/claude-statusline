# Строка состояния для Claude Code

Строка состояния (`statusLine`) для [Claude Code](https://claude.com/claude-code): папка, ветка git, модель, остаток контекста и лимитов шкалами, текущая задача.

```
~/project main* v1.2.0 │ Opus 5.5 v2.1.285 (48210t) │ ctx ━━━━━━━━━━ 72%  5h ━━━━━━━━━━ 90%  all ━━━━━━━━━━ 64%  fable ━━━━━━━━━━ 81%
❯ последняя реплика пользователя
```

Что показывает:

- **папка** — рабочая директория, `$HOME` сокращён до `~`;
- **ветка git** со звёздочкой, если есть незакоммиченные изменения, и **версия проекта** из `package.json`;
- **модель** и **версия Claude Code**, токены последнего запроса;
- **шкалы остатка** — контекст (`ctx`), лимит на 5 часов (`5h`), недельный по всем моделям (`all`) и недельный по Fable (`fable`). Везде показан остаток, а не расход: шкала при выгорании пустеет. Цвет: серо-синий — запас есть, песочный — меньше половины, красный — меньше 20%;
- **агент** и **режим Vim**, если включены;
- **текущая задача** — последняя реплика пользователя из транскрипта, отдельной строкой.

Шкалы встают в ту же строку, только если помещаются целиком, иначе уходят на свою строку.

## Установка

Нужен `jq` (`brew install jq`).

```sh
git clone https://github.com/russelgal/claude-statusline.git
cp claude-statusline/statusline-command.sh claude-statusline/usage-fetch.sh ~/.claude/
chmod +x ~/.claude/statusline-command.sh ~/.claude/usage-fetch.sh
```

В `~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }
}
```

## Лимит Fable (`usage-fetch.sh`)

Во вход `statusLine` приходят только лимиты `five_hour` и `seven_day`; помодельного недельного лимита там нет. `usage-fetch.sh` раз в 2 минуты фоном берёт его из `https://api.anthropic.com/api/oauth/usage` (тот же источник, что у команды `/usage`) и кладёт в `~/.claude/cache/usage.json`; строка состояния только читает этот файл и в сеть не ходит.

- Работает на **macOS**: токен Claude Code берётся из связки ключей (`security find-generic-password -s "Claude Code-credentials"`) при каждом запуске и никуда, кроме api.anthropic.com, не отправляется. В файлах токенов нет.
- Эндпоинт не документирован и может измениться. Без `usage-fetch.sh` строка работает, просто без шкалы `fable`.

## Лицензия

MIT
