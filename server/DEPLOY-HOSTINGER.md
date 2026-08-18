# Ocean Cast API — развёртывание на Hostinger

Проверено на локальном Apache 2.4 + PHP через CGI: тот же режим, в котором
LiteSpeed на Hostinger отдаёт PHP, включая обрезание заголовка `Authorization`.
Оба набора тестов (67 проверок API и 44 контрактных) проходят через этот
`.htaccess` полностью.

---

## 1. Что куда класть

Загрузите **содержимое** папки `server/` прямо в `public_html`:

```
public_html/
├── .htaccess          ← корневой роутинг и защита (уже в репозитории)
├── .env               ← создать из .env.example (никогда не публичен)
├── public/
│   ├── index.php      ← единственный исполняемый файл
│   └── .htaccess
├── src/               ← закрыт .htaccess
├── database/          ← закрыт .htaccess
├── migrations/        ← закрыт .htaccess
├── tools/             ← закрыт .htaccess
└── storage/           ← логи, закрыт .htaccess
```

В File Manager включите **Settings → Show hidden files**, иначе `.htaccess` и
`.env` не будут видны и не загрузятся.

Если API живёт на поддомене (`api.example.com`), у него свой корень — кладите
файлы туда же, ничего менять не нужно. Если кладёте в подпапку
(`public_html/api`), то в `.htaccess` смените `RewriteBase /` на
`RewriteBase /api/`, а в `.env` укажите `APP_BASE_PATH=api`.

---

## 2. База данных

1. hPanel → **Базы данных → MySQL**: создайте базу и пользователя, выдайте
   пользователю все права. Имя будет с префиксом, например `u123456789_oceancast`.
2. hPanel → **phpMyAdmin**, слева **выберите созданную базу**.
3. Вкладка **Импорт** → файл `database/oceancast_full.sql` → **Вперёд**.

После импорта внизу появится список из **21 таблицы**. Файл безопасно
импортировать повторно — все таблицы создаются через `CREATE TABLE IF NOT EXISTS`.

Если хостинг на MariaDB и импорт ругается на `utf8mb4_0900_ai_ci`, замените в
файле эту коллацию на `utf8mb4_general_ci` и импортируйте снова.

---

## 3. Файл .env

Скопируйте `.env.example` в `.env` и заполните:

```ini
APP_ENV=production
APP_KEY=<64 случайных символа>
FORCE_HTTPS=true

DB_HOST=localhost
DB_NAME=u123456789_oceancast
DB_USER=u123456789_oceancast
DB_PASSWORD=<пароль из hPanel>

LOG_FILE=
```

`APP_KEY` — 32+ символа. Сгенерировать можно так (или любым генератором паролей
на 64 символа):

```bash
php -r "echo bin2hex(random_bytes(32));"
```

`APP_KEY` участвует в HMAC для лимитов и хешей IP в журнале безопасности. При
смене ключа сбрасываются счётчики лимитов — пароли и токены не затрагиваются.

`LOG_FILE` оставьте пустым: логи пойдут в `storage/api.log`, который закрыт
`.htaccess`. Папке `storage` нужны права **755** (при ошибке записи — 775).

---

## 4. Проверка

```
https://ваш-домен/v1/health
```

Должно вернуться:

```json
{"status":"ok","time":"…","version":"v1"}
```

Затем убедитесь, что закрытое действительно закрыто — каждый адрес должен
отдавать **403**:

```
https://ваш-домен/.env
https://ваш-домен/src/Core/Config.php
https://ваш-домен/database/oceancast_full.sql
https://ваш-домен/storage/api.log
https://ваш-домен/tools/migrate.php
```

А `https://ваш-домен/` должен отдать `404 {"error":{"code":"not_found"…}}` —
это нормально, корень не является эндпоинтом.

---

## 5. Подключение приложения

В приложении: **Settings → Account & Sync → Server address** → `https://ваш-домен`
(без `/public` и без слэша в конце). Затем **Sign in or create an account**.

---

## 6. Если что-то не работает

| Симптом | Причина и что делать |
|---|---|
| Все запросы `401 missing_token`, хотя вход выполнен | Заголовок `Authorization` не доходит до PHP. Именно это лечат строки блока 2 в `.htaccess` — проверьте, что корневой `.htaccess` загрузился и не переписан панелью |
| `403 https_required` при обращении по https | TLS завершается на прокси, PHP видит http. Поставьте `TRUST_FORWARDED_PROTO=true` в `.env` |
| `500 server_misconfigured` | Не задан `APP_KEY` в `.env` (или файл не загрузился — включите показ скрытых файлов) |
| `404 not_found` на все адреса, включая `/v1/health` | API лежит в подпапке: задайте `APP_BASE_PATH` и `RewriteBase` |
| `403` вообще на всё, включая `/v1/health` | На хостинге нет mod_rewrite. `.htaccess` намеренно закрывает сайт целиком, чтобы не отдать исходники. Включите mod_rewrite / LiteSpeed |
| Ошибка подключения к БД | Имя базы и пользователя на Hostinger идут с префиксом `uXXXXXXXX_`; `DB_HOST=localhost` |
| `500` без подробностей | Смотрите `storage/api.log` через File Manager. В `APP_ENV=production` клиенту отдаётся общий текст, детали только в лог |

---

## 7. После установки

- **Удалите `tools/`** с боевого сервера, если не планируете запускать миграции
  и тесты по SSH. Каталог и так закрыт, но лишнего кода на проде лучше не держать.
- Настройте cron раз в час (hPanel → Дополнительно → Cron Jobs):

  ```
  /usr/bin/php /home/uXXXXXXXX/public_html/tools/cleanup.php
  ```

  Он удаляет протухшие токены, счётчики лимитов, ключи идемпотентности и
  записи журнала старше `AUDIT_RETENTION_DAYS`.
- PHP: **8.1 или новее** (рекомендуется 8.2/8.3), нужны расширения `pdo_mysql`,
  `mbstring`, `json`, `openssl`. Версия переключается в hPanel → PHP Configuration.
