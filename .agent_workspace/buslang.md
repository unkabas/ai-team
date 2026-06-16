# buslang — компактный язык координации (жёсткое сжатие)

Цель: минимум токенов в машинном слое (event_log, communication_bus, error_dump,
state.json). Человекочитаемый слой (context.md, ideas.md, decisions.md) пишется
обычным языком — buslang там НЕ применяется.

Не пиши эти строки руками — вызывай `./bus <cmd>`, он генерирует канонический
формат. Раздел ниже — чтобы ты умел ЧИТАТЬ ленту.

## Словарь

| Код | Значение | | Код | Значение |
|-----|----------|-|-----|----------|
| `~path` | файл | | `bl` | backlog |
| `+`  | создал  | | `ip` | in_progress |
| `-`  | удалил  | | `rv` | review |
| `x`  | сбой    | | `dn` | done |
| `#T7`| ссылка на задачу T-007 | | `>` | направлено к |

## Форматы строк

**event_log.md** — `<DDThhmm> <agent> ~<file> <result>`
```
16T2240 alice ~src/pay.py ok
16T2241 bob ~src/api.py x timeout
```

**communication_bus.md**
```
Q alice>bob: какой формат токена?           вопрос
A bob #T7: JWT, 15 мин                       ответ (ref = задача или тема)
CR alice>bob#T7| mutex душит параллелизм |> lease на задачу
```
`CR` = **C**ritique + **R**ecommendation. Главное правило команды:
**критикуешь — предлагай.** Часть после `|>` обязательна; `./bus cr` отклонит
критику без предложения. Никогда не возражай молча — всегда давай альтернативу.

**error_dump.md** — `<DDThhmm> <agent> ! <message>`
```
16T2242 bob ! NPE в pay.py:42, null token из cache
```

## Команды, генерирующие buslang

```
./bus log    <agent> <file> <result...>
./bus error  <agent> <message...>
./bus ask    <agent> <target> <question...>
./bus answer <agent> <ref> <text...>
./bus cr     <agent> <target> <task> --crit "..." --prop "..."
```
