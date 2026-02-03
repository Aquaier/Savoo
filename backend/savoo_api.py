import os
import re
import sqlite3
import csv
import io
import base64
import binascii
import json
import logging
import secrets
from datetime import datetime, date, timedelta
from contextlib import closing
from typing import Any, Dict, Optional, Tuple, List

import requests

from flask import Flask, jsonify, request, make_response, g
from functools import wraps
from flask_cors import CORS
import bcrypt

DATABASE_PATH = os.path.join(os.path.dirname(__file__), 'savoo.db')

if not logging.getLogger().handlers:
    logging.basicConfig(level=logging.INFO)

logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
app.secret_key = os.environ.get('SAVOO_SECRET_KEY', 'savoo_super_secret_key')

EMAIL_REGEX = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PASSWORD_REGEX = re.compile(r"^(?=.*[A-Za-z])(?=.*\d).{6,}$")
NBP_API_URL = 'https://api.nbp.pl/api/exchangerates/tables/A?format=json'
BUDGET_ALERT_THRESHOLD = 0.9
BASE_CURRENCY = 'PLN'
CURRENCY_CACHE_PATH = os.path.join(os.path.dirname(__file__), 'currency_rates_cache.json')
CURRENCY_CACHE_TTL = timedelta(hours=24)

SECURITY_QUESTION_CHOICES = {
    'pet_name': 'Imię Twojego pupila',
    'childhood_friend': 'Imię Twojego najlepszego przyjaciela z dzieciństwa',
    'birth_city': 'Miasto urodzenia Twojej mamy',
    'favorite_teacher': 'Imię ulubionego nauczyciela',
    'first_school': 'Nazwa Twojej pierwszej szkoły',
}
RESET_TOKEN_TTL = timedelta(minutes=15)


def end_of_month(value: date) -> date:
    """Zwraca ostatni dzień miesiąca dla podanej daty."""
    next_month = (value.replace(day=28) + timedelta(days=4)).replace(day=1)
    return next_month - timedelta(days=1)


def get_default_expense_categories() -> List[Dict[str, str]]:
    """Zwraca listę startowych kategorii wydatków używanych podczas rejestracji."""
    return [
        {
            'name': 'Zakupy spożywcze',
            'color': '#27ae60',
            'icon_url': 'https://img.icons8.com/color/96/ingredients.png',
        },
        {
            'name': 'Restauracje i kawiarnie',
            'color': '#e67e22',
            'icon_url': 'https://img.icons8.com/color/96/restaurant.png',
        },
        {
            'name': 'Transport',
            'color': '#2980b9',
            'icon_url': 'https://img.icons8.com/color/96/car.png',
        },
        {
            'name': 'Mieszkanie i rachunki',
            'color': '#8e44ad',
            'icon_url': 'https://img.icons8.com/color/96/home.png',
        },
        {
            'name': 'Rozrywka',
            'color': '#f39c12',
            'icon_url': 'https://img.icons8.com/color/96/popcorn.png',
        },
        {
            'name': 'Zdrowie i uroda',
            'color': '#d35400',
            'icon_url': 'https://img.icons8.com/color/96/spa.png',
        },
        {
            'name': 'Edukacja',
            'color': '#16a085',
            'icon_url': 'https://img.icons8.com/color/96/graduation-cap.png',
        },
        {
            'name': 'Podróże',
            'color': '#1abc9c',
            'icon_url': 'https://img.icons8.com/color/96/around-the-globe.png',
        },
        {
            'name': 'Prezenty',
            'color': '#c0392b',
            'icon_url': 'https://img.icons8.com/color/96/gift.png',
        },
        {
            'name': 'Hobby i sport',
            'color': '#9b59b6',
            'icon_url': 'https://img.icons8.com/color/96/dumbbell.png',
        },
        {
            'name': 'Zwierzęta',
            'color': '#2c3e50',
            'icon_url': 'https://img.icons8.com/color/96/dog.png',
        },
        {
            'name': 'Inne wydatki',
            'color': '#7f8c8d',
            'icon_url': 'https://img.icons8.com/color/96/more.png',
        },
    ]

ALLOWED_TRANSACTION_KINDS = {
    'general',
    'household',
    'entertainment',
    'savings',
    'travel',
    'education',
    'health',
    'investment',
    'salary',
    'bonus',
    'gift',
    'other',
}

ALLOWED_BUDGET_TYPES = {
    'household',
    'entertainment',
    'groceries',
    'travel',
    'savings',
    'health',
    'education',
    'custom',
}

DEFAULT_TRANSACTION_KIND = 'general'
DEFAULT_BUDGET_TYPE = 'custom'


def get_db_connection():
    """Otwiera lokalną bazę SQLite i zwraca połączenie z rekordami jako słownikami."""
    conn = sqlite3.connect(DATABASE_PATH)
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('PRAGMA synchronous=NORMAL')
    conn.execute('PRAGMA wal_autocheckpoint=1000')
    conn.row_factory = sqlite3.Row
    return conn


def init_db_for_connection(conn: sqlite3.Connection) -> None:
    """Tworzy wszystkie wymagane tabele wraz z kluczami obcymi w podanym połączeniu."""
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT,
            display_name TEXT,
            default_currency TEXT DEFAULT 'PLN',
            monthly_income REAL,
            monthly_income_currency TEXT DEFAULT 'PLN',
            monthly_income_day INTEGER,
            role TEXT DEFAULT 'user',
            security_question_key TEXT,
            security_answer_hash TEXT,
            reset_token TEXT,
            reset_token_expires_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            last_login_at TEXT
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            type TEXT CHECK(type IN ('income','expense')) NOT NULL,
            color TEXT DEFAULT '#2ecc71',
            icon_url TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS budget_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            category_id INTEGER,
            type TEXT CHECK(type IN ('income','expense','transfer')) NOT NULL,
            amount REAL NOT NULL,
            currency TEXT DEFAULT 'PLN',
            converted_amount REAL,
            note TEXT,
            kind TEXT DEFAULT 'general',
            budget_id INTEGER,
            occurred_on TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
            FOREIGN KEY(budget_id) REFERENCES budgets(id) ON DELETE SET NULL
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS recurring_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            category_id INTEGER,
            type TEXT CHECK(type IN ('income','expense','transfer')) NOT NULL,
            amount REAL NOT NULL,
            currency TEXT DEFAULT 'PLN',
            note TEXT,
            frequency TEXT CHECK(frequency IN ('daily','weekly','monthly','quarterly','yearly')) NOT NULL,
            start_date TEXT NOT NULL,
            next_occurrence TEXT NOT NULL,
            end_date TEXT,
            last_generated TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS savings_goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            target_amount REAL NOT NULL,
            current_amount REAL DEFAULT 0,
            deadline TEXT,
            category_id INTEGER,
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS savings_goal_contributions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            goal_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(goal_id) REFERENCES savings_goals(id) ON DELETE CASCADE
        );
        """
    )
    cursor.execute(
        """
        CREATE TRIGGER IF NOT EXISTS trg_savings_goal_contributions_insert
        AFTER INSERT ON savings_goal_contributions
        BEGIN
            UPDATE savings_goals
            SET current_amount = current_amount + NEW.amount,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.goal_id;
        END;
        """
    )
    cursor.execute(
        """
        CREATE TRIGGER IF NOT EXISTS trg_savings_goal_contributions_update
        AFTER UPDATE ON savings_goal_contributions
        BEGIN
            UPDATE savings_goals
            SET current_amount = current_amount - OLD.amount + NEW.amount,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.goal_id;
        END;
        """
    )
    cursor.execute(
        """
        CREATE TRIGGER IF NOT EXISTS trg_savings_goal_contributions_delete
        AFTER DELETE ON savings_goal_contributions
        BEGIN
            UPDATE savings_goals
            SET current_amount = MAX(current_amount - OLD.amount, 0),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = OLD.goal_id;
        END;
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS currency_rates (
            currency_code TEXT PRIMARY KEY,
            rate_to_pln REAL NOT NULL,
            fetched_at TEXT NOT NULL
        );
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS budgets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            category_id INTEGER,
            name TEXT NOT NULL,
            limit_amount REAL NOT NULL,
            period TEXT CHECK(period IN ('weekly','monthly','quarterly','custom')) DEFAULT 'monthly',
            budget_type TEXT DEFAULT 'custom',
            start_date TEXT,
            end_date TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL
        );
        """
    )
    conn.commit()


def init_db():
    """Tworzy wszystkie wymagane tabele wraz z kluczami obcymi, jeśli jeszcze nie istnieją."""
    with closing(get_db_connection()) as conn:
        init_db_for_connection(conn)


def column_exists(cursor, table: str, column: str) -> bool:
    """Sprawdza w sqlite_master, czy dana tabela zawiera wskazaną kolumnę."""
    cursor.execute(f"PRAGMA table_info({table})")
    return any(row[1] == column for row in cursor.fetchall())


def table_exists(cursor, table: str) -> bool:
    """Weryfikuje obecność tabeli w bazie, aby uniknąć duplikowania migracji."""
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
    return cursor.fetchone() is not None


def migrate_db_for_connection(conn: sqlite3.Connection) -> None:
    """Dodaje brakujące kolumny i pola kontrolne w podanym połączeniu."""
    cursor = conn.cursor()
    if not table_exists(cursor, 'budget_types'):
        cursor.execute(
            """
            CREATE TABLE budget_types (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(user_id, name),
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            """
        )
    if not column_exists(cursor, 'transactions', 'currency'):
        cursor.execute("ALTER TABLE transactions ADD COLUMN currency TEXT DEFAULT 'PLN'")
    if not column_exists(cursor, 'transactions', 'converted_amount'):
        cursor.execute("ALTER TABLE transactions ADD COLUMN converted_amount REAL")
    if not column_exists(cursor, 'transactions', 'kind'):
        cursor.execute("ALTER TABLE transactions ADD COLUMN kind TEXT DEFAULT 'general'")
    if not column_exists(cursor, 'transactions', 'budget_id'):
        cursor.execute("ALTER TABLE transactions ADD COLUMN budget_id INTEGER")
    if not column_exists(cursor, 'budgets', 'last_notified_at'):
        cursor.execute("ALTER TABLE budgets ADD COLUMN last_notified_at TEXT")
    if not column_exists(cursor, 'budgets', 'budget_type'):
        cursor.execute("ALTER TABLE budgets ADD COLUMN budget_type TEXT DEFAULT 'custom'")
    if not column_exists(cursor, 'savings_goals', 'current_amount'):
        cursor.execute("ALTER TABLE savings_goals ADD COLUMN current_amount REAL DEFAULT 0")
    if not column_exists(cursor, 'categories', 'icon_url'):
        cursor.execute("ALTER TABLE categories ADD COLUMN icon_url TEXT")
    if not column_exists(cursor, 'users', 'role'):
        cursor.execute("ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'user'")
    if not column_exists(cursor, 'users', 'security_question_key'):
        cursor.execute('ALTER TABLE users ADD COLUMN security_question_key TEXT')
    if not column_exists(cursor, 'users', 'security_answer_hash'):
        cursor.execute('ALTER TABLE users ADD COLUMN security_answer_hash TEXT')
    if not column_exists(cursor, 'users', 'last_login_at'):
        cursor.execute("ALTER TABLE users ADD COLUMN last_login_at TEXT")
    if not column_exists(cursor, 'users', 'updated_at'):
        cursor.execute("ALTER TABLE users ADD COLUMN updated_at TEXT DEFAULT CURRENT_TIMESTAMP")
    if not column_exists(cursor, 'users', 'monthly_income_day'):
        cursor.execute('ALTER TABLE users ADD COLUMN monthly_income_day INTEGER')
    if not column_exists(cursor, 'users', 'monthly_income_currency'):
        cursor.execute("ALTER TABLE users ADD COLUMN monthly_income_currency TEXT DEFAULT 'PLN'")
    conn.commit()


def migrate_db():
    """Dodaje brakujące kolumny i pola kontrolne, synchronizując schemat bazy z kodem."""
    with closing(get_db_connection()) as conn:
        migrate_db_for_connection(conn)



init_db()
migrate_db()


@app.route('/')
def home():
    """Zwraca prostą odpowiedź JSON informującą, że API działa."""
    return jsonify({'message': 'Welcome to the Savoo Budget API'})


def is_valid_email(email: str) -> bool:
    """Waliduje adres e-mail za pomocą zdefiniowanego wyrażenia regularnego."""
    return bool(email and EMAIL_REGEX.match(email))


def is_strong_password(password: str) -> bool:
    """Sprawdza, czy hasło ma minimum 6 znaków oraz zawiera litery i cyfry."""
    return bool(password and PASSWORD_REGEX.match(password))


def hash_password(password: str) -> str:
    """Szyfruje hasło użytkownika algorytmem bcrypt przed zapisaniem."""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def check_password(password: str, hashed: str) -> bool:
    """Porównuje podane hasło z przechowywanym hashem i zwraca wynik uwierzytelnienia."""
    return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))


def slugify(value: str) -> str:
    """Przekształca dowolny tekst w prosty identyfikator nadający się na slug."""
    slug = re.sub(r'[^a-z0-9]+', '-', value.lower())
    slug = slug.strip('-')
    return slug or 'category'

    def normalize_security_question_key(value: Optional[str]) -> Optional[str]:
        """Porządkuje klucz pytania bezpieczeństwa do porównania ze słownikiem."""
        if not value:
            return None
        return value.strip().lower()


    def is_security_question_valid(value: Optional[str]) -> bool:
        """Weryfikuje, czy przekazany klucz pytania należy do dostępnej listy."""
        normalized = normalize_security_question_key(value)
        return normalized in SECURITY_QUESTION_CHOICES


    def generate_reset_token() -> str:
        """Generuje jednorazowy token używany do resetu hasła."""
        return secrets.token_urlsafe(32)


def normalize_security_question_key(value: Optional[str]) -> Optional[str]:
    """Porządkuje klucz pytania bezpieczeństwa do porównania ze słownikiem."""
    if not value:
        return None
    return value.strip().lower()


def is_security_question_valid(value: Optional[str]) -> bool:
    """Weryfikuje, czy przekazany klucz pytania należy do dostępnej listy."""
    normalized = normalize_security_question_key(value)
    return normalized in SECURITY_QUESTION_CHOICES


def generate_reset_token() -> str:
    """Generuje jednorazowy token używany do resetu hasła."""
    return secrets.token_urlsafe(32)


def log_budget_notification(budget_name: str, message: str) -> None:
    """Zapisuje komunikat budżetowy w logach jako substytut wysyłki e-mail."""
    logger.info("[Budżet] %s - %s", budget_name, message)


def _store_currency_rates(rates: Dict[str, float], fetched_at: str) -> None:
    """Czyści tabelę kursów i zapisuje w niej przekazane notowania walut."""
    sanitized: Dict[str, float] = {'PLN': 1.0}
    for code, value in rates.items():
        if not code:
            continue
        try:
            sanitized[code.upper()] = float(value)
        except (TypeError, ValueError):
            continue

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute('DELETE FROM currency_rates')
        for currency_code, rate in sanitized.items():
            cursor.execute(
                'INSERT OR REPLACE INTO currency_rates (currency_code, rate_to_pln, fetched_at) VALUES (?, ?, ?)',
                (currency_code, rate, fetched_at),
            )
        conn.commit()


def ensure_currency_rates(force_refresh: bool = False) -> None:
    """Pilnuje aktualności kursów walut, korzystając z cache albo NBP."""
    now = datetime.utcnow()
    cache_data: Optional[Dict[str, Any]] = None
    if not force_refresh and os.path.exists(CURRENCY_CACHE_PATH):
        try:
            with open(CURRENCY_CACHE_PATH, 'r', encoding='utf-8') as cache_file:
                cache_data = json.load(cache_file)
        except (OSError, json.JSONDecodeError):
            cache_data = None

    if cache_data and not force_refresh:
        fetched_at_str = cache_data.get('fetched_at')
        rates = cache_data.get('rates') or {}
        cache_timestamp: Optional[datetime] = None
        if fetched_at_str:
            try:
                cache_timestamp = datetime.fromisoformat(fetched_at_str)
            except ValueError:
                cache_timestamp = None
        if cache_timestamp and now - cache_timestamp <= CURRENCY_CACHE_TTL:
            _store_currency_rates(rates, fetched_at_str)
            return

    try:
        response = requests.get(NBP_API_URL, timeout=5)
        response.raise_for_status()
        payload = response.json()
        raw_rates = payload[0]['rates'] if payload else []
    except Exception as exc:
        logger.warning('Nie udało się pobrać kursów walut: %s', exc)
        if cache_data:
            fetched_at_str = cache_data.get('fetched_at') or now.isoformat()
            rates = cache_data.get('rates') or {}
            _store_currency_rates(rates, fetched_at_str)
        return

    fetched_at = datetime.utcnow().isoformat()
    extracted_rates: Dict[str, float] = {}
    for item in raw_rates:
        code = item.get('code')
        value = item.get('mid')
        if code and value is not None:
            try:
                extracted_rates[code.upper()] = float(value)
            except (TypeError, ValueError):
                continue

    _store_currency_rates(extracted_rates, fetched_at)

    cache_payload = {
        'fetched_at': fetched_at,
        'rates': extracted_rates,
    }
    try:
        with open(CURRENCY_CACHE_PATH, 'w', encoding='utf-8') as cache_file:
            json.dump(cache_payload, cache_file, ensure_ascii=False, indent=2)
    except OSError as exc:
        logger.warning('Nie udało się zapisać cache kursów walut: %s', exc)


def get_exchange_rate(currency: str) -> float:
    """Zwraca kurs danej waluty względem PLN, odczytując go z lokalnej tabeli."""
    if not currency:
        return 1.0
    currency = currency.upper()
    if currency == 'PLN':
        return 1.0
    ensure_currency_rates()
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT rate_to_pln FROM currency_rates WHERE currency_code = ?', (currency,))
        row = cursor.fetchone()
        return float(row['rate_to_pln']) if row else 1.0


def convert_amount(amount: float, source_currency: str, target_currency: str) -> float:
    """Przelicza kwotę między walutami z użyciem aktualnych kursów."""
    if amount is None:
        return 0.0
    source = (source_currency or 'PLN').upper()
    target = (target_currency or 'PLN').upper()
    if source == target:
        return float(amount)
    source_rate = get_exchange_rate(source)
    target_rate = get_exchange_rate(target)
    if target_rate == 0:
        return float(amount) * source_rate
    amount_pln = float(amount) * source_rate
    if target == 'PLN':
        return amount_pln
    return amount_pln / target_rate


def normalize_currency(value: Optional[str], fallback: str = BASE_CURRENCY) -> str:
    """Normalizuje kod waluty do formatu ISO (np. PLN, EUR)."""
    if not value:
        return fallback
    normalized = value.strip().upper()
    return normalized or fallback


def convert_to_base(amount: float, currency: Optional[str]) -> float:
    """Konwertuje kwotę do waluty bazowej (PLN)."""
    return convert_amount(amount, normalize_currency(currency), BASE_CURRENCY)


def convert_from_base(amount: float, currency: Optional[str]) -> float:
    """Konwertuje kwotę z waluty bazowej (PLN) do wskazanej waluty."""
    return convert_amount(amount, BASE_CURRENCY, normalize_currency(currency))


def get_user_by_email(cursor, email: str):
    """Pobiera rekord użytkownika na podstawie adresu e-mail."""
    cursor.execute('SELECT * FROM users WHERE email = ?', (email,))
    return cursor.fetchone()


def get_user_by_id(cursor, user_id: int):
    """Zwraca rekord użytkownika wskazanego identyfikatorem."""
    cursor.execute('SELECT * FROM users WHERE id = ?', (user_id,))
    return cursor.fetchone()


def authenticate_user(email: str, password: str) -> Optional[sqlite3.Row]:
    """Normalizuje dane logowania i zwraca użytkownika tylko przy poprawnym haśle."""
    normalized_email = (email or '').strip().lower()
    if not normalized_email or not password:
        return None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user = get_user_by_email(cursor, normalized_email)
        if not user:
            return None
        if not check_password(password, user['password_hash']):
            return None
        return user


def _parse_basic_auth_header(auth_header: str) -> Tuple[Optional[str], Optional[str]]:
    """Dekoduje nagłówek Basic Auth i wyciąga z niego e-mail oraz hasło."""
    if not auth_header or not auth_header.startswith('Basic '):
        return None, None
    encoded = auth_header.split(' ', 1)[1].strip()
    try:
        decoded = base64.b64decode(encoded).decode('utf-8')
    except (binascii.Error, UnicodeDecodeError):
        return None, None
    email, _, password = decoded.partition(':')
    email = email.strip().lower() if email else None
    return email, password


def auth_required(roles: Optional[Tuple[str, ...]] = None):
    """Buduje dekorator wymuszający poprawne logowanie i odpowiednią rolę."""
    def decorator(func):
        """Opakowuje endpoint logiką autoryzacji i przekazuje rolę dalej."""
        @wraps(func)
        def wrapper(*args, **kwargs):
            """Sprawdza nagłówek Basic Auth i egzekwuje dostęp lub zwraca błąd."""
            header = request.headers.get('Authorization', '')
            email, password = _parse_basic_auth_header(header)
            if not email or not password:
                return jsonify({'success': False, 'message': 'Wymagane uwierzytelnienie.'}), 401

            user = authenticate_user(email, password)
            if not user:
                return jsonify({'success': False, 'message': 'Nieprawidłowe dane logowania.'}), 401

            role = user['role'] or 'user'
            if roles and role not in roles:
                return jsonify({'success': False, 'message': 'Brak wymaganych uprawnień.'}), 403

            g.current_user = dict(user)
            g.auth_email = email
            return func(*args, **kwargs)

        return wrapper

    return decorator

def seed_default_categories(user_id: int) -> None:
    """Zakłada nowe konto startowymi kategoriami wydatków, jeśli jeszcze ich nie ma."""
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT name FROM categories WHERE user_id = ? AND type = ?', (user_id, 'expense'))
        existing_names = {row['name'] for row in cursor.fetchall()}
        inserted = False
        for template in get_default_expense_categories():
            if template['name'] in existing_names:
                continue
            cursor.execute(
                'INSERT INTO categories (user_id, name, type, color, icon_url) VALUES (?, ?, ?, ?, ?)',
                (
                    user_id,
                    template['name'],
                    'expense',
                    template['color'],
                    template['icon_url'],
                ),
            )
            category_id = cursor.lastrowid
            cursor.execute('SELECT * FROM categories WHERE id = ?', (category_id,))
            row = cursor.fetchone()
            if row:
                inserted = True
            existing_names.add(template['name'])
        if inserted:
            conn.commit()


def add_months(base_date: date, months: int) -> date:
    """Dodaje określoną liczbę miesięcy do daty, pilnując liczby dni w miesiącu."""
    month = base_date.month - 1 + months
    year = base_date.year + month // 12
    month = month % 12 + 1
    day = min(base_date.day, [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1])
    return date(year, month, day)


def next_recurring_date(current_date: date, frequency: str) -> date:
    """Wyznacza kolejną datę wystąpienia cyklicznej transakcji."""
    if frequency == 'daily':
        return current_date + timedelta(days=1)
    if frequency == 'weekly':
        return current_date + timedelta(weeks=1)
    if frequency == 'monthly':
        return add_months(current_date, 1)
    if frequency == 'quarterly':
        return add_months(current_date, 3)
    if frequency == 'yearly':
        return add_months(current_date, 12)
    return current_date + timedelta(days=30)


def process_recurring_transactions(user_id: int) -> None:
    """Generuje zaległe cykliczne transakcje i aktualizuje ich harmonogram."""
    today = date.today()
    today_str = today.isoformat()
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT * FROM recurring_transactions WHERE user_id = ? AND next_occurrence <= ? AND (end_date IS NULL OR next_occurrence <= end_date)",
            (user_id, today_str),
        )
        recurrences = [dict(row) for row in cursor.fetchall()]
        if not recurrences:
            return

        user = get_user_by_id(cursor, user_id)
        user_currency = user['default_currency'] if user else 'PLN'

        for recurrence in recurrences:
            occurrence_date = datetime.fromisoformat(recurrence['next_occurrence']).date()
            end_date = datetime.fromisoformat(recurrence['end_date']).date() if recurrence.get('end_date') else None
            next_date = occurrence_date
            while next_date <= today and (end_date is None or next_date <= end_date):
                txn_currency = (recurrence.get('currency') or user_currency or 'PLN').upper()
                converted_amount = convert_amount(recurrence['amount'], txn_currency, user_currency)
                cursor.execute(
                    'INSERT INTO transactions (user_id, category_id, type, amount, currency, converted_amount, note, occurred_on) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    (
                        user_id,
                        recurrence.get('category_id'),
                        recurrence['type'],
                        float(recurrence['amount']),
                        txn_currency,
                        converted_amount,
                        recurrence.get('note'),
                        next_date.isoformat(),
                    ),
                )
                recurrence['last_generated'] = next_date.isoformat()
                next_date = next_recurring_date(next_date, recurrence['frequency'])

            cursor.execute(
                'UPDATE recurring_transactions SET next_occurrence = ?, last_generated = ? WHERE id = ?',
                (next_date.isoformat(), recurrence.get('last_generated'), recurrence['id']),
            )
        conn.commit()


def maybe_send_budget_notification(conn, cursor, budget: dict) -> bool:
    """Sprawdza wykorzystanie budżetu i loguje ostrzeżenie, ograniczając się do lokalnych komunikatów."""
    limit_amount = float(budget.get('limit_amount') or 0)
    spent = float(budget.get('spent_amount') or 0)
    if limit_amount <= 0:
        return False
    utilization = spent / limit_amount if limit_amount else 0
    over_limit = spent > limit_amount
    threshold_hit = utilization >= BUDGET_ALERT_THRESHOLD or over_limit
    if not threshold_hit:
        return False

    last_notified = budget.get('last_notified_at')
    if last_notified and last_notified[:10] == date.today().isoformat():
        return False

    if over_limit:
        body = f"Budżet przekroczony: wydatki {spent:.2f} / limit {limit_amount:.2f}."
    else:
        body = f"Budżet osiągnął {utilization * 100:.0f}% progu. Pozostało {limit_amount - spent:.2f}."

    log_budget_notification(budget.get('name') or 'Budżet', body)
    timestamp = datetime.utcnow().isoformat()
    cursor.execute(
        'UPDATE budgets SET last_notified_at = ? WHERE id = ?',
        (timestamp, budget['id']),
    )
    budget['last_notified_at'] = timestamp
    conn.commit()
    return True


@app.route('/currencies', methods=['GET'])
def list_currencies():
    """Udostępnia endpoint zwracający listę kursów walut zapisanych w cache."""
    refresh = request.args.get('refresh', '').strip().lower() == 'true'
    ensure_currency_rates(force_refresh=refresh)
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT currency_code, rate_to_pln, fetched_at FROM currency_rates ORDER BY currency_code ASC')
        rows = cursor.fetchall()
    currencies = [
        {
            'code': row['currency_code'],
            'rate_to_pln': row['rate_to_pln'],
            'fetched_at': row['fetched_at'],
        }
        for row in rows
    ]
    return jsonify({'success': True, 'currencies': currencies})


@app.route('/register', methods=['POST'])
def register():
    """Obsługuje rejestrację użytkownika z walidacją i zasiewem danych startowych."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    display_name = data.get('display_name', '').strip()
    security_question_key = normalize_security_question_key(data.get('security_question_key'))
    security_answer = (data.get('security_answer') or '').strip()

    if not is_valid_email(email):
        return jsonify({'success': False, 'message': 'Podaj poprawny adres e-mail.'}), 400
    if not is_strong_password(password):
        return jsonify({'success': False, 'message': 'Hasło musi mieć min. 6 znaków, zawierać literę i cyfrę.'}), 400
    if not is_security_question_valid(security_question_key):
        return jsonify({'success': False, 'message': 'Wybierz pytanie bezpieczeństwa z listy.'}), 400
    if len(security_answer) < 3:
        return jsonify({'success': False, 'message': 'Odpowiedź na pytanie bezpieczeństwa musi mieć co najmniej 3 znaki.'}), 400
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        if get_user_by_email(cursor, email):
            return jsonify({'success': False, 'message': 'Konto o podanym e-mailu już istnieje.'}), 409

        password_hash = hash_password(password)
        security_answer_hash = hash_password(security_answer)
        cursor.execute(
            'INSERT INTO users (email, password_hash, display_name, role, security_question_key, security_answer_hash) VALUES (?, ?, ?, ?, ?, ?)',
            (
                email,
                password_hash,
                display_name or None,
                'user',
                security_question_key,
                security_answer_hash,
            ),
        )
        user_id = cursor.lastrowid
        conn.commit()
        cursor.execute('SELECT * FROM users WHERE id = ?', (user_id,))
        user_row = cursor.fetchone()

    if not user_row:
        return jsonify({'success': False, 'message': 'Nie udało się utworzyć konta.'}), 500

    seed_default_categories(user_row['id'])

    monthly_income = user_row['monthly_income']
    monthly_income_currency = user_row['monthly_income_currency'] or user_row['default_currency'] or 'PLN'
    user_payload = {
        'id': user_row['id'],
        'email': user_row['email'],
        'display_name': user_row['display_name'],
        'role': user_row['role'],
        'default_currency': user_row['default_currency'],
        'monthly_income': monthly_income,
        'monthly_income_currency': monthly_income_currency,
        'monthly_income_day': user_row['monthly_income_day'],
    }

    return jsonify({
        'success': True,
        'message': 'Konto zostało utworzone.',
        'user': user_payload,
    }), 201


@app.route('/login', methods=['POST'])
def login():
    """Weryfikuje dane logowania, aktualizuje ostatnie logowanie i zwraca profil."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')

    if not email or not password:
        return jsonify({'success': False, 'message': 'Wprowadź e-mail i hasło.'}), 400

    user_row = None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_row = get_user_by_email(cursor, email)
        if not user_row:
            return jsonify({'success': False, 'message': 'Nieprawidłowy e-mail lub hasło.'}), 401

        if not check_password(password, user_row['password_hash']):
            return jsonify({'success': False, 'message': 'Nieprawidłowy e-mail lub hasło.'}), 401

        timestamp = datetime.utcnow().isoformat()
        cursor.execute(
            'UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?',
            (timestamp, timestamp, user_row['id']),
        )
        conn.commit()
        cursor.execute('SELECT * FROM users WHERE id = ?', (user_row['id'],))
        user_row = cursor.fetchone()

    if not user_row:
        return jsonify({'success': False, 'message': 'Nie udało się zalogować użytkownika.'}), 500

    login_income = user_row['monthly_income']
    monthly_income_currency = user_row['monthly_income_currency'] or user_row['default_currency'] or 'PLN'
    user_payload = {
        'id': user_row['id'],
        'email': user_row['email'],
        'display_name': user_row['display_name'],
        'role': user_row['role'],
        'default_currency': user_row['default_currency'],
        'monthly_income': login_income,
        'monthly_income_currency': monthly_income_currency,
        'monthly_income_day': user_row['monthly_income_day'],
    }

    return jsonify({
        'success': True,
        'user': user_payload,
    })


@app.route('/logout', methods=['POST'])
def logout():
    """Zwraca potwierdzenie wylogowania, pozwalając klientowi wyczyścić sesję."""
    return jsonify({'success': True, 'message': 'Wylogowano.'})


@app.route('/forgot-password/verify', methods=['POST'])
def forgot_password_verify():
    """Weryfikuje pytanie bezpieczeństwa i generuje tymczasowy token resetu hasła."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    question_key = normalize_security_question_key(data.get('security_question_key'))
    answer = (data.get('security_answer') or '').strip()

    if not is_valid_email(email):
        return jsonify({'success': False, 'message': 'Niepoprawny adres e-mail.'}), 400
    if not is_security_question_valid(question_key):
        return jsonify({'success': False, 'message': 'Wybierz pytanie bezpieczeństwa z listy.'}), 400
    if not answer:
        return jsonify({'success': False, 'message': 'Podaj odpowiedź na pytanie bezpieczeństwa.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user = get_user_by_email(cursor, email)
        if not user:
            return jsonify({'success': False, 'message': 'Nie znaleziono konta lub brak skonfigurowanego pytania bezpieczeństwa.'}), 404
        stored_question_key = user['security_question_key']
        if not stored_question_key:
            return jsonify({'success': False, 'message': 'Nie znaleziono konta lub brak skonfigurowanego pytania bezpieczeństwa.'}), 404
        if stored_question_key != question_key:
            return jsonify({'success': False, 'message': 'Wybrane pytanie nie zgadza się z zapisanym.'}), 400
        stored_answer_hash = user['security_answer_hash']
        if not stored_answer_hash or not check_password(answer, stored_answer_hash):
            return jsonify({'success': False, 'message': 'Niepoprawna odpowiedź na pytanie bezpieczeństwa.'}), 400

        token = generate_reset_token()
        expires_at = (datetime.utcnow() + RESET_TOKEN_TTL).isoformat()
        cursor.execute(
            'UPDATE users SET reset_token = ?, reset_token_expires_at = ? WHERE id = ?',
            (token, expires_at, user['id']),
        )
        conn.commit()

    return jsonify({
        'success': True,
        'message': 'Odpowiedź poprawna. Możesz ustawić nowe hasło.',
        'reset_token': token,
        'token_expires_at': expires_at,
    })


@app.route('/forgot-password/reset', methods=['POST'])
def forgot_password_reset():
    """Aktualizuje hasło użytkownika na podstawie tokenu resetu."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    reset_token = (data.get('reset_token') or '').strip()
    new_password = data.get('new_password', '')
    confirm_password = data.get('confirm_password', '')

    if not is_valid_email(email):
        return jsonify({'success': False, 'message': 'Niepoprawny adres e-mail.'}), 400
    if not reset_token:
        return jsonify({'success': False, 'message': 'Brak tokenu resetu.'}), 400
    if new_password != confirm_password:
        return jsonify({'success': False, 'message': 'Hasła muszą być identyczne.'}), 400
    if not is_strong_password(new_password):
        return jsonify({'success': False, 'message': 'Nowe hasło nie spełnia wymagań złożoności.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user = get_user_by_email(cursor, email)
        if not user:
            return jsonify({'success': False, 'message': 'Niepoprawny token resetu lub konto.'}), 400
        stored_token = user['reset_token']
        if not stored_token:
            return jsonify({'success': False, 'message': 'Niepoprawny token resetu lub konto.'}), 400
        if stored_token != reset_token:
            return jsonify({'success': False, 'message': 'Token resetu nie zgadza się.'}), 400

        expires_at_raw = user['reset_token_expires_at']
        if not expires_at_raw:
            return jsonify({'success': False, 'message': 'Token resetu wygasł. Spróbuj ponownie.'}), 400
        try:
            expires_at = datetime.fromisoformat(expires_at_raw)
        except ValueError:
            expires_at = datetime.utcnow() - timedelta(minutes=1)
        if expires_at < datetime.utcnow():
            return jsonify({'success': False, 'message': 'Token resetu wygasł. Spróbuj ponownie.'}), 400

        password_hash = hash_password(new_password)
        cursor.execute(
            'UPDATE users SET password_hash = ?, reset_token = NULL, reset_token_expires_at = NULL WHERE id = ?',
            (password_hash, user['id']),
        )
        conn.commit()

    return jsonify({'success': True, 'message': 'Hasło zostało zaktualizowane. Możesz się zalogować.'})


@app.route('/profile', methods=['GET', 'PUT'])
@auth_required()
def profile():
    """Pozwala odczytać lub zaktualizować profil zalogowanego użytkownika."""
    current_user = g.current_user

    if request.method == 'GET':
        target_email = request.args.get('email', '').strip().lower() or current_user['email']
        if target_email != current_user['email'] and current_user.get('role') != 'admin':
            return jsonify({'success': False, 'message': 'Brak uprawnień do podglądu profilu innego użytkownika.'}), 403

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user = get_user_by_email(cursor, target_email)
            if not user:
                return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404
            monthly_income = user['monthly_income']
            monthly_income_currency = user['monthly_income_currency'] or user['default_currency'] or 'PLN'
            return jsonify({
                'success': True,
                'profile': {
                    'email': user['email'],
                    'display_name': user['display_name'],
                    'default_currency': user['default_currency'],
                    'monthly_income': monthly_income,
                    'monthly_income_currency': monthly_income_currency,
                    'monthly_income_day': user['monthly_income_day'],
                    'role': user['role'],
                    'created_at': user['created_at'],
                    'last_login_at': user['last_login_at'],
                }
            })

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or current_user['email']
    if target_email != current_user['email'] and current_user.get('role') != 'admin':
        return jsonify({'success': False, 'message': 'Brak uprawnień do edycji innego profilu.'}), 403

    updated_user = None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user = get_user_by_email(cursor, target_email)
        if not user:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

        default_currency = data.get('default_currency') or user['default_currency'] or 'PLN'
        if isinstance(default_currency, str):
            default_currency = default_currency.strip().upper() or 'PLN'

        income_currency = data.get('monthly_income_currency') or user.get('monthly_income_currency') or default_currency
        if isinstance(income_currency, str):
            income_currency = income_currency.strip().upper() or default_currency

        monthly_income_value = user['monthly_income']
        if 'monthly_income' in data:
            monthly_income_raw = data.get('monthly_income', 0)
            if isinstance(monthly_income_raw, str):
                monthly_income_raw = monthly_income_raw.replace(',', '.').strip()
            try:
                monthly_income_value = float(monthly_income_raw)
            except (TypeError, ValueError):
                return jsonify({'success': False, 'message': 'Niepoprawna kwota miesięcznego dochodu.'}), 400

        existing_income_day = user['monthly_income_day']
        if existing_income_day is not None:
            try:
                existing_income_day = int(existing_income_day)
            except (TypeError, ValueError):
                existing_income_day = None

        income_day_value = existing_income_day
        if 'monthly_income_day' in data:
            income_day_raw = data.get('monthly_income_day')
            if income_day_raw in (None, '', 'null'):
                income_day_value = None
            else:
                try:
                    income_day_candidate = int(income_day_raw)
                except (TypeError, ValueError):
                    return jsonify({'success': False, 'message': 'Niepoprawny dzień wypłaty.'}), 400
                if income_day_candidate < 1 or income_day_candidate > 31:
                    return jsonify({'success': False, 'message': 'Dzień wypłaty musi być z zakresu 1-31.'}), 400
                income_day_value = income_day_candidate

        timestamp = datetime.utcnow().isoformat()
        cursor.execute(
            'UPDATE users SET display_name = ?, default_currency = ?, monthly_income = ?, monthly_income_currency = ?, monthly_income_day = ?, updated_at = ? WHERE email = ?',
            (
                data.get('display_name'),
                default_currency,
                monthly_income_value,
                income_currency,
                income_day_value,
                timestamp,
                target_email,
            ),
        )
        conn.commit()
        cursor.execute('SELECT * FROM users WHERE email = ?', (target_email,))
        updated_user = cursor.fetchone()

    return jsonify({'success': True, 'message': 'Profil zaktualizowany.'})


def resolve_user_id(cursor, email: Optional[str]):
    """Na podstawie bieżącej sesji i e-maila określa ID użytkownika przy zachowaniu ról."""
    current = getattr(g, 'current_user', None)

    if current:
        if email and email != current['email'] and current.get('role') != 'admin':
            return None
        if not email or email == current['email']:
            return current['id']

    if not email:
        return None

    user = get_user_by_email(cursor, email)
    if not user:
        return None
    if current and current.get('role') != 'admin' and user['id'] != current['id']:
        return None
    return user['id']


@app.route('/categories', methods=['GET', 'POST'])
@auth_required()
def categories():
    """Zwraca listę kategorii użytkownika lub tworzy nową po weryfikacji danych."""
    if request.method == 'GET':
        target_email = request.args.get('email', '').strip().lower() or None

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
            cursor.execute(
                'SELECT * FROM categories WHERE user_id = ? ORDER BY type DESC, created_at DESC',
                (user_id,),
            )
            items = [dict(row) for row in cursor.fetchall()]

        return jsonify({'success': True, 'categories': items})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None
    name = (data.get('name') or '').strip()
    category_type = (data.get('type') or 'expense').strip().lower()
    color = data.get('color', '#2ecc71')
    icon_url = (data.get('icon_url') or '').strip() or None

    if not name or category_type not in {'income', 'expense'}:
        return jsonify({'success': False, 'message': 'Brak wymaganych danych.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        cursor.execute(
            'INSERT INTO categories (user_id, name, type, color, icon_url) VALUES (?, ?, ?, ?, ?)',
            (user_id, name, category_type, color, icon_url),
        )
        category_id = cursor.lastrowid
        cursor.execute('SELECT * FROM categories WHERE id = ?', (category_id,))
        category_row = cursor.fetchone()
        conn.commit()

    return jsonify({
        'success': True,
        'message': 'Kategoria dodana.',
        'category': dict(category_row) if category_row else None,
    })


@app.route('/categories/<int:category_id>', methods=['PUT', 'DELETE'])
@auth_required()
def category_detail(category_id):
    """Aktualizuje albo usuwa konkretną kategorię należącą do użytkownika."""
    if request.method == 'DELETE':
        target_email = request.args.get('email', '').strip().lower() or None
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
            cursor.execute('DELETE FROM categories WHERE id = ? AND user_id = ?', (category_id, user_id))
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'Nie znaleziono kategorii.'}), 404
            conn.commit()
        return jsonify({'success': True, 'message': 'Kategoria usunięta.'})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None
    name = (data.get('name') or '').strip()
    category_type = (data.get('type') or '').strip().lower()
    color = data.get('color')
    icon_url = data.get('icon_url')

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        cursor.execute('SELECT * FROM categories WHERE id = ? AND user_id = ?', (category_id, user_id))
        existing = cursor.fetchone()
        if not existing:
            return jsonify({'success': False, 'message': 'Nie znaleziono kategorii.'}), 404

        updates = {
            'name': name or None,
            'type': category_type if category_type in {'income', 'expense'} else None,
            'color': color,
            'icon_url': icon_url,
        }

        set_parts = []
        params = []
        for key, value in updates.items():
            if value is not None:
                set_parts.append(f"{key} = ?")
                params.append(value)

        if not set_parts:
            return jsonify({'success': False, 'message': 'Brak danych do aktualizacji.'}), 400

        params.extend([category_id, user_id])
        cursor.execute(
            f"UPDATE categories SET {', '.join(set_parts)} WHERE id = ? AND user_id = ?",
            params,
        )
        cursor.execute('SELECT * FROM categories WHERE id = ? AND user_id = ?', (category_id, user_id))
        category_row = cursor.fetchone()
        conn.commit()

    return jsonify({'success': True, 'message': 'Kategoria zaktualizowana.'})


@app.route('/budget-types', methods=['GET', 'POST'])
@auth_required()
def budget_types():
    """Zwraca listę typów budżetów użytkownika lub tworzy nowy."""
    if request.method == 'GET':
        target_email = request.args.get('email', '').strip().lower() or None

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
            cursor.execute(
                'SELECT * FROM budget_types WHERE user_id = ? ORDER BY created_at DESC',
                (user_id,),
            )
            items = [dict(row) for row in cursor.fetchall()]

        return jsonify({'success': True, 'budget_types': items})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None
    raw_name = (data.get('name') or '').strip()
    if len(raw_name) < 2:
        return jsonify({'success': False, 'message': 'Nazwa rodzaju budżetu jest zbyt krótka.'}), 400

    normalized = raw_name.lower()
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        try:
            cursor.execute(
                'INSERT INTO budget_types (user_id, name) VALUES (?, ?)',
                (user_id, normalized),
            )
        except sqlite3.IntegrityError:
            return jsonify({'success': False, 'message': 'Taki rodzaj budżetu już istnieje.'}), 409
        budget_type_id = cursor.lastrowid
        cursor.execute('SELECT * FROM budget_types WHERE id = ?', (budget_type_id,))
        row = cursor.fetchone()
        conn.commit()

    return jsonify({
        'success': True,
        'message': 'Rodzaj budżetu dodany.',
        'budget_type': dict(row) if row else None,
    })


@app.route('/budget-types/<int:type_id>', methods=['DELETE'])
@auth_required()
def budget_type_detail(type_id: int):
    """Usuwa wybrany typ budżetu użytkownika."""
    target_email = request.args.get('email', '').strip().lower() or None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
        cursor.execute('DELETE FROM budget_types WHERE id = ? AND user_id = ?', (type_id, user_id))
        if cursor.rowcount == 0:
            return jsonify({'success': False, 'message': 'Nie znaleziono rodzaju budżetu.'}), 404
        conn.commit()
    return jsonify({'success': True, 'message': 'Rodzaj budżetu usunięty.'})


def parse_iso_date(value: Optional[str]) -> str:
    """Normalizuje łańcuch na datę ISO, a w razie błędu przyjmuje dzisiejszą."""
    if not value:
        return date.today().isoformat()
    try:
        return datetime.fromisoformat(value).date().isoformat()
    except ValueError:
        return date.today().isoformat()


@app.route('/recurring-transactions', methods=['GET', 'POST'])
@auth_required()
def recurring_transactions():
    """Listuje bądź dodaje cykliczne transakcje po sprawdzeniu uprawnień."""
    if request.method == 'GET':
        target_email = request.args.get('email', '').strip().lower() or None
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
            cursor.execute(
                'SELECT * FROM recurring_transactions WHERE user_id = ? ORDER BY created_at DESC',
                (user_id,),
            )
            items = [dict(row) for row in cursor.fetchall()]
        return jsonify({'success': True, 'recurring_transactions': items})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None
    amount = data.get('amount')
    txn_type = (data.get('type') or '').strip().lower()
    frequency = (data.get('frequency') or '').strip().lower()
    start_date = parse_iso_date(data.get('start_date') or date.today().isoformat())
    end_date = parse_iso_date(data.get('end_date')) if data.get('end_date') else None
    currency = (data.get('currency') or '').strip().upper() or None
    category_id = data.get('category_id')

    if amount is None or txn_type not in {'income', 'expense', 'transfer'}:
        return jsonify({'success': False, 'message': 'Brak wymaganych danych.'}), 400
    if frequency not in {'daily', 'weekly', 'monthly', 'quarterly', 'yearly'}:
        return jsonify({'success': False, 'message': 'Niepoprawna częstotliwość.'}), 400
    if txn_type == 'expense' and not category_id:
        return jsonify({'success': False, 'message': 'Wybierz kategorię wydatku przed zapisaniem cyklicznej transakcji.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        if category_id:
            cursor.execute('SELECT id FROM categories WHERE id = ? AND user_id = ?', (category_id, user_id))
            if not cursor.fetchone():
                return jsonify({'success': False, 'message': 'Wybrana kategoria nie istnieje.'}), 404

        cursor.execute(
            'INSERT INTO recurring_transactions (user_id, category_id, type, amount, currency, note, frequency, start_date, next_occurrence, end_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            (
                user_id,
                category_id,
                txn_type,
                float(amount),
                currency,
                data.get('note'),
                frequency,
                start_date,
                start_date,
                end_date,
            ),
        )
        conn.commit()

    return jsonify({'success': True, 'message': 'Cykliczna transakcja dodana.'})


@app.route('/recurring-transactions/<int:recurring_id>', methods=['PUT', 'DELETE'])
@auth_required()
def recurring_transaction_detail(recurring_id):
    """Pozwala zmienić lub usunąć pojedynczą cykliczną transakcję użytkownika."""
    if request.method == 'DELETE':
        target_email = request.args.get('email', '').strip().lower() or None
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
            cursor.execute('DELETE FROM recurring_transactions WHERE id = ? AND user_id = ?', (recurring_id, user_id))
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'Nie znaleziono pozycji.'}), 404
            conn.commit()
        return jsonify({'success': True, 'message': 'Pozycja usunięta.'})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        cursor.execute('SELECT * FROM recurring_transactions WHERE id = ? AND user_id = ?', (recurring_id, user_id))
        existing = cursor.fetchone()
        if not existing:
            return jsonify({'success': False, 'message': 'Nie znaleziono pozycji.'}), 404

        updates: Dict[str, Any] = {}
        if data.get('category_id') is not None:
            updates['category_id'] = data.get('category_id')
            cursor.execute('SELECT id FROM categories WHERE id = ? AND user_id = ?', (updates['category_id'], user_id))
            if not cursor.fetchone():
                return jsonify({'success': False, 'message': 'Wybrana kategoria nie istnieje.'}), 404
        if data.get('type') is not None:
            new_type = (data.get('type') or '').strip().lower()
            if new_type not in {'income', 'expense', 'transfer'}:
                return jsonify({'success': False, 'message': 'Niepoprawny typ transakcji.'}), 400
            updates['type'] = new_type
        if data.get('amount') is not None:
            updates['amount'] = float(data.get('amount'))
        if data.get('currency') is not None:
            updates['currency'] = (data.get('currency') or '').strip().upper()
        if data.get('note') is not None:
            updates['note'] = data.get('note')
        if data.get('frequency') is not None:
            new_frequency = (data.get('frequency') or '').strip().lower()
            if new_frequency not in {'daily', 'weekly', 'monthly', 'quarterly', 'yearly'}:
                return jsonify({'success': False, 'message': 'Niepoprawna częstotliwość.'}), 400
            updates['frequency'] = new_frequency
        if data.get('start_date') is not None:
            start_override = parse_iso_date(data.get('start_date'))
            updates['start_date'] = start_override
            updates['next_occurrence'] = start_override
        if data.get('end_date') is not None:
            updates['end_date'] = parse_iso_date(data.get('end_date')) if data.get('end_date') else None
        if data.get('next_occurrence') is not None:
            updates['next_occurrence'] = parse_iso_date(data.get('next_occurrence'))

        if not updates:
            return jsonify({'success': False, 'message': 'Brak danych do aktualizacji.'}), 400

        final_type = updates.get('type', existing['type'])
        final_category_id = updates.get('category_id', existing['category_id'])
        if final_type == 'expense' and not final_category_id:
            return jsonify({'success': False, 'message': 'Wybierz kategorię wydatku.'}), 400

        set_parts = []
        params: list[Any] = []
        for key, value in updates.items():
            set_parts.append(f"{key} = ?")
            params.append(value)

        params.extend([recurring_id, user_id])
        cursor.execute(
            f"UPDATE recurring_transactions SET {', '.join(set_parts)} WHERE id = ? AND user_id = ?",
            params,
        )
        conn.commit()

    return jsonify({'success': True, 'message': 'Pozycja zaktualizowana.'})


@app.route('/transactions', methods=['GET', 'POST'])
@auth_required()
def transactions():
    """Pobiera transakcje użytkownika lub zapisuje nową po przeliczeniach walut."""
    if request.method == 'GET':
        target_email = request.args.get('email', '').strip().lower() or None
        start = request.args.get('start_date') or None
        end = request.args.get('end_date') or None

        user_id: Optional[int] = None
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        process_recurring_transactions(user_id)

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user = get_user_by_id(cursor, user_id)
            user_currency = normalize_currency(user['default_currency'] if user else None)
            query = (
                'SELECT t.*, b.name AS budget_name, b.budget_type AS budget_type '
                'FROM transactions t '
                'LEFT JOIN budgets b ON t.budget_id = b.id '
                'WHERE t.user_id = ?'
            )
            params: list[Any] = [user_id]
            if start:
                query += ' AND t.occurred_on >= ?'
                params.append(start)
            if end:
                query += ' AND t.occurred_on <= ?'
                params.append(end)
            query += ' ORDER BY t.occurred_on DESC, t.created_at DESC'
            cursor.execute(query, params)
            items = []
            for row in cursor.fetchall():
                item = dict(row)
                base_amount = item.get('converted_amount')
                if base_amount is None:
                    base_amount = convert_to_base(
                        float(item.get('amount') or 0),
                        normalize_currency(item.get('currency') or user_currency),
                    )
                item['display_amount'] = convert_from_base(base_amount, user_currency)
                item['display_currency'] = user_currency
                items.append(item)
        return jsonify({'success': True, 'transactions': items})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None
    amount = data.get('amount')
    txn_type = (data.get('type') or '').strip().lower()
    occurred_on = parse_iso_date(data.get('occurred_on'))
    currency = (data.get('currency') or '').strip().upper() or None
    category_id = data.get('category_id')
    note = data.get('note')
    raw_kind = (data.get('kind') or DEFAULT_TRANSACTION_KIND).strip().lower()
    kind = raw_kind if raw_kind in ALLOWED_TRANSACTION_KINDS else DEFAULT_TRANSACTION_KIND
    raw_budget_id = data.get('budget_id')
    budget_id = None
    if raw_budget_id not in (None, ''):
        try:
            budget_id = int(raw_budget_id)
            if budget_id <= 0:
                budget_id = None
        except (TypeError, ValueError):
            return jsonify({'success': False, 'message': 'Niepoprawny identyfikator budżetu.'}), 400

    if amount is None or txn_type not in {'income', 'expense', 'transfer'}:
        return jsonify({'success': False, 'message': 'Brak wymaganych danych.'}), 400
    if txn_type == 'expense' and not category_id and not budget_id:
        return jsonify({'success': False, 'message': 'Wybierz kategorię lub budżet dla wydatku.'}), 400

    user_id: Optional[int] = None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        if category_id:
            cursor.execute('SELECT id FROM categories WHERE id = ? AND user_id = ?', (category_id, user_id))
            if not cursor.fetchone():
                return jsonify({'success': False, 'message': 'Wybrana kategoria nie istnieje.'}), 404
        if budget_id:
            cursor.execute('SELECT id FROM budgets WHERE id = ? AND user_id = ?', (budget_id, user_id))
            if not cursor.fetchone():
                return jsonify({'success': False, 'message': 'Wybrany budżet nie istnieje.'}), 404

        user = get_user_by_id(cursor, user_id)
        user_currency = normalize_currency(user['default_currency'] if user else None)
        txn_currency = normalize_currency(currency or user_currency)
        try:
            numeric_amount = float(amount)
        except (TypeError, ValueError):
            return jsonify({'success': False, 'message': 'Kwota musi być liczbą.'}), 400
        converted_amount = convert_to_base(numeric_amount, txn_currency)

        cursor.execute(
            'INSERT INTO transactions (user_id, category_id, type, amount, currency, converted_amount, note, kind, budget_id, occurred_on) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            (
                user_id,
                category_id,
                txn_type,
                numeric_amount,
                txn_currency,
                converted_amount,
                note,
                kind,
                budget_id,
                occurred_on,
            ),
        )
        transaction_id = cursor.lastrowid
        conn.commit()

    return jsonify({'success': True, 'message': 'Transakcja dodana.'})


@app.route('/transactions/<int:transaction_id>', methods=['PUT', 'DELETE'])
@auth_required()
def transaction_detail(transaction_id: int):
    """Aktualizuje albo usuwa wskazaną transakcję po dodatkowych walidacjach."""
    if request.method == 'DELETE':
        target_email = request.args.get('email', '').strip().lower() or None
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, target_email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403
            cursor.execute('DELETE FROM transactions WHERE id = ? AND user_id = ?', (transaction_id, user_id))
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'Nie znaleziono transakcji.'}), 404
            conn.commit()
        return jsonify({'success': True, 'message': 'Transakcja usunięta.'})

    data = request.get_json(silent=True) or {}
    target_email = data.get('email', '').strip().lower() or None

    user_id: Optional[int] = None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, target_email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Brak uprawnień lub użytkownik nie istnieje.'}), 403

        cursor.execute('SELECT * FROM transactions WHERE id = ? AND user_id = ?', (transaction_id, user_id))
        existing = cursor.fetchone()
        if not existing:
            return jsonify({'success': False, 'message': 'Nie znaleziono transakcji.'}), 404

        updates: Dict[str, Any] = {}
        if data.get('category_id') is not None:
            updates['category_id'] = data.get('category_id')
            if updates['category_id']:
                cursor.execute('SELECT id FROM categories WHERE id = ? AND user_id = ?', (updates['category_id'], user_id))
                if not cursor.fetchone():
                    return jsonify({'success': False, 'message': 'Wybrana kategoria nie istnieje.'}), 404
        if 'budget_id' in data:
            raw_budget_id = data.get('budget_id')
            if raw_budget_id in (None, ''):
                updates['budget_id'] = None
            else:
                try:
                    budget_value = int(raw_budget_id)
                except (TypeError, ValueError):
                    return jsonify({'success': False, 'message': 'Niepoprawny identyfikator budżetu.'}), 400
                if budget_value <= 0:
                    updates['budget_id'] = None
                else:
                    cursor.execute('SELECT id FROM budgets WHERE id = ? AND user_id = ?', (budget_value, user_id))
                    if not cursor.fetchone():
                        return jsonify({'success': False, 'message': 'Wybrany budżet nie istnieje.'}), 404
                    updates['budget_id'] = budget_value
        if data.get('type') is not None:
            new_type = (data.get('type') or '').strip().lower()
            if new_type not in {'income', 'expense', 'transfer'}:
                return jsonify({'success': False, 'message': 'Niepoprawny typ transakcji.'}), 400
            updates['type'] = new_type
        if data.get('kind') is not None:
            kind_value = (data.get('kind') or DEFAULT_TRANSACTION_KIND).strip().lower()
            if kind_value not in ALLOWED_TRANSACTION_KINDS:
                return jsonify({'success': False, 'message': 'Niepoprawny rodzaj transakcji.'}), 400
            updates['kind'] = kind_value
        if data.get('amount') is not None:
            try:
                updates['amount'] = float(data.get('amount'))
            except (TypeError, ValueError):
                return jsonify({'success': False, 'message': 'Kwota musi być liczbą.'}), 400
        if data.get('currency') is not None:
            updates['currency'] = (data.get('currency') or '').strip().upper() or None
        if data.get('note') is not None:
            updates['note'] = data.get('note')
        if data.get('occurred_on') is not None:
            updates['occurred_on'] = parse_iso_date(data.get('occurred_on'))

        user = get_user_by_id(cursor, user_id)
        user_currency = normalize_currency(user['default_currency'] if user else None)

        amount_value = updates.get('amount', existing['amount'])
        currency_value = updates.get('currency', existing['currency'] or user_currency)
        if amount_value is not None:
            txn_currency = normalize_currency(currency_value or user_currency)
            converted_amount = convert_to_base(float(amount_value), txn_currency)
            updates['amount'] = float(amount_value)
            updates['currency'] = txn_currency
            updates['converted_amount'] = converted_amount

        final_type = updates.get('type', existing['type'])
        final_category_id = updates.get('category_id', existing['category_id'])
        final_budget_id = updates.get('budget_id', existing['budget_id'])
        if final_type == 'expense' and not final_category_id and not final_budget_id:
            return jsonify({'success': False, 'message': 'Wybierz kategorię lub budżet dla wydatku.'}), 400

        if not updates:
            return jsonify({'success': False, 'message': 'Brak danych do aktualizacji.'}), 400

        set_parts = [f"{key} = ?" for key in updates.keys()]
        params = list(updates.values())
        set_clause = ', '.join(set_parts + ['updated_at = CURRENT_TIMESTAMP'])

        params.extend([transaction_id, user_id])
        cursor.execute(
            f"UPDATE transactions SET {set_clause} WHERE id = ? AND user_id = ?",
            params,
        )
        conn.commit()

    return jsonify({'success': True, 'message': 'Transakcja zaktualizowana.'})


@app.route('/budgets', methods=['GET', 'POST'])
def budgets():
    """Zwraca budżety z wyliczoną statystyką albo dodaje nowy na podstawie żądania."""
    if request.method == 'GET':
        email = request.args.get('email', '').strip().lower()
        if not email:
            return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404
        process_recurring_transactions(user_id)

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT * FROM budgets WHERE user_id = ? ORDER BY created_at DESC', (user_id,))
            raw_budgets = [dict(row) for row in cursor.fetchall()]

            user = get_user_by_id(cursor, user_id)
            user_currency = normalize_currency(user['default_currency'] if user else None)

            month_start = date.today().replace(day=1)
            month_end = end_of_month(date.today())

            cursor.execute(
                'SELECT id, budget_id, category_id, amount, currency, occurred_on '
                'FROM transactions WHERE user_id = ? AND type = ?',
                (user_id, 'expense'),
            )
            raw_transactions = [dict(row) for row in cursor.fetchall()]

            transactions = []
            for txn in raw_transactions:
                occurred_raw = (txn.get('occurred_on') or '')[:10]
                try:
                    occurred_date = datetime.fromisoformat(occurred_raw).date()
                except ValueError:
                    continue
                amount_pln = convert_to_base(
                    float(txn.get('amount') or 0),
                    txn.get('currency') or BASE_CURRENCY,
                )
                transactions.append({
                    'budget_id': txn.get('budget_id'),
                    'category_id': txn.get('category_id'),
                    'occurred_on': occurred_date,
                    'amount_pln': amount_pln,
                })

            for budget in raw_budgets:
                start_str = budget['start_date'] or month_start.isoformat()
                end_str = budget['end_date'] or month_end.isoformat()
                try:
                    start_date = datetime.fromisoformat(start_str).date()
                except ValueError:
                    start_date = month_start
                try:
                    end_date = datetime.fromisoformat(end_str).date()
                except ValueError:
                    end_date = month_end

                spent_pln = 0.0
                total_transactions = 0
                fallback_spent_pln = 0.0
                fallback_total = 0

                for txn in transactions:
                    if txn['occurred_on'] < start_date or txn['occurred_on'] > end_date:
                        continue
                    if txn['budget_id'] == budget['id']:
                        spent_pln += txn['amount_pln']
                        total_transactions += 1
                    elif budget['category_id'] and txn['budget_id'] is None and txn['category_id'] == budget['category_id']:
                        fallback_spent_pln += txn['amount_pln']
                        fallback_total += 1

                if (spent_pln == 0) and budget['category_id']:
                    spent_pln = fallback_spent_pln
                    total_transactions = fallback_total

                budget['budget_type'] = budget.get('budget_type') or DEFAULT_BUDGET_TYPE
                limit_pln = float(budget.get('limit_amount') or 0)

                notify_payload = {
                    **budget,
                    'limit_amount': limit_pln,
                    'spent_amount': spent_pln,
                }
                maybe_send_budget_notification(conn, cursor, notify_payload)

                limit_display = convert_from_base(limit_pln, user_currency)
                spent_display = convert_from_base(spent_pln, user_currency)

                budget['limit_amount'] = limit_display
                budget['spent_amount'] = spent_display
                budget['transaction_count'] = int(total_transactions or 0)
                budget['remaining'] = limit_display - spent_display
                budget['currency'] = user_currency
                if limit_display:
                    budget['utilization'] = spent_display / limit_display if limit_display else 0
                else:
                    budget['utilization'] = None

            return jsonify({'success': True, 'budgets': raw_budgets})

    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    name = (data.get('name') or '').strip()
    limit_amount = data.get('limit_amount')
    period = data.get('period', 'monthly')
    raw_budget_type = data.get('budget_type')
    budget_type = (raw_budget_type or DEFAULT_BUDGET_TYPE).strip().lower()

    if not email or not name or limit_amount is None:
        return jsonify({'success': False, 'message': 'Brak wymaganych danych.'}), 400
    if period not in {'weekly', 'monthly', 'quarterly', 'custom'}:
        return jsonify({'success': False, 'message': 'Niepoprawny okres budżetu.'}), 400
    if not budget_type:
        budget_type = DEFAULT_BUDGET_TYPE

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

        user = get_user_by_id(cursor, user_id)
        input_currency = normalize_currency(data.get('currency') or (user['default_currency'] if user else None))
        try:
            limit_amount_value = float(limit_amount)
        except (TypeError, ValueError):
            return jsonify({'success': False, 'message': 'Limit budżetu musi być liczbą.'}), 400
        limit_amount_base = convert_to_base(limit_amount_value, input_currency)

        cursor.execute(
            'INSERT INTO budgets (user_id, category_id, name, limit_amount, period, budget_type, start_date, end_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            (
                user_id,
                data.get('category_id'),
                name,
                limit_amount_base,
                period,
                budget_type,
                data.get('start_date'),
                data.get('end_date'),
            ),
        )
        cursor.lastrowid
        conn.commit()

    return jsonify({'success': True, 'message': 'Budżet dodany.'})


@app.route('/budgets/<int:budget_id>', methods=['PUT', 'DELETE'])
def budget_detail(budget_id):
    """Obsługuje aktualizację bądź usunięcie konkretnego budżetu użytkownika."""
    if request.method == 'DELETE':
        email = request.args.get('email', '').strip().lower()
        if not email:
            return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400
        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404
            cursor.execute('DELETE FROM budgets WHERE id = ? AND user_id = ?', (budget_id, user_id))
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'Nie znaleziono budżetu.'}), 404
            conn.commit()
        return jsonify({'success': True, 'message': 'Budżet usunięty.'})

    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    if not email:
        return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400

    updates = {
        'name': (data.get('name') or '').strip() or None,
        'limit_amount': data.get('limit_amount'),
        'period': data['period'] if data.get('period') in {'weekly', 'monthly', 'quarterly', 'custom'} else None,
        'category_id': data.get('category_id'),
        'start_date': data.get('start_date'),
        'end_date': data.get('end_date'),
    }
    if data.get('budget_type') is not None:
        normalized_type = (data.get('budget_type') or '').strip().lower()
        updates['budget_type'] = normalized_type or DEFAULT_BUDGET_TYPE

    user_id = None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

        if updates.get('limit_amount') is not None:
            user = get_user_by_id(cursor, user_id)
            input_currency = normalize_currency(data.get('currency') or (user['default_currency'] if user else None))
            try:
                updates['limit_amount'] = convert_to_base(float(updates['limit_amount']), input_currency)
            except (TypeError, ValueError):
                return jsonify({'success': False, 'message': 'Limit budżetu musi być liczbą.'}), 400

        set_parts = []
        params = []
        for key, value in updates.items():
            if value is not None:
                set_parts.append(f"{key} = ?")
                params.append(value)
        if not set_parts:
            return jsonify({'success': False, 'message': 'Brak danych do aktualizacji.'}), 400

        params.extend([budget_id, user_id])
        cursor.execute(
            f"UPDATE budgets SET {', '.join(set_parts)} WHERE id = ? AND user_id = ?",
            params,
        )
        if cursor.rowcount == 0:
            return jsonify({'success': False, 'message': 'Nie znaleziono budżetu.'}), 404
        conn.commit()

    return jsonify({'success': True, 'message': 'Budżet zaktualizowany.'})


@app.route('/savings-goals', methods=['GET', 'POST'])
def savings_goals():
    """Listuje cele oszczędnościowe użytkownika lub tworzy nowy cel."""
    if request.method == 'GET':
        email = request.args.get('email', '').strip().lower()
        if not email:
            return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400

        with closing(get_db_connection()) as conn:
            cursor = conn.cursor()
            user_id = resolve_user_id(cursor, email)
            if not user_id:
                return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

            user = get_user_by_id(cursor, user_id)
            user_currency = normalize_currency(user['default_currency'] if user else None)

            cursor.execute('SELECT * FROM savings_goals WHERE user_id = ? ORDER BY created_at DESC', (user_id,))
            goals = []
            for row in cursor.fetchall():
                goal = dict(row)
                cursor.execute(
                    'SELECT COALESCE(SUM(amount), 0) AS total FROM savings_goal_contributions WHERE goal_id = ?',
                    (goal['id'],),
                )
                contributed_pln = cursor.fetchone()['total']
                target_pln = float(goal.get('target_amount') or 0)
                current_pln = float(goal.get('current_amount') or 0)

                goal['contributed_amount'] = convert_from_base(contributed_pln, user_currency)
                goal['target_amount'] = convert_from_base(target_pln, user_currency)
                goal['current_amount'] = convert_from_base(current_pln, user_currency)
                goal['remaining_amount'] = max(goal['target_amount'] - goal['current_amount'], 0)
                goal['progress_percent'] = (
                    round((current_pln / target_pln) * 100, 2)
                    if target_pln
                    else None
                )
                goal['currency'] = user_currency
                goals.append(goal)
            return jsonify({'success': True, 'goals': goals})

    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    name = (data.get('name') or '').strip()
    target_amount = data.get('target_amount')

    if not email or not name or target_amount is None:
        return jsonify({'success': False, 'message': 'Brak wymaganych danych.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

        user = get_user_by_id(cursor, user_id)
        input_currency = normalize_currency(data.get('currency') or (user['default_currency'] if user else None))
        try:
            target_pln = convert_to_base(float(target_amount), input_currency)
            current_pln = convert_to_base(float(data.get('current_amount', 0) or 0), input_currency)
        except (TypeError, ValueError):
            return jsonify({'success': False, 'message': 'Niepoprawna kwota celu.'}), 400

        cursor.execute(
            'INSERT INTO savings_goals (user_id, name, target_amount, current_amount, deadline, category_id, is_active) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (
                user_id,
                name,
                target_pln,
                current_pln,
                data.get('deadline'),
                data.get('category_id'),
                1 if data.get('is_active', True) else 0,
            ),
        )
        goal_id = cursor.lastrowid
        conn.commit()

    return jsonify({'success': True, 'message': 'Cel oszczędnościowy dodany.'})


@app.route('/savings-goals/<int:goal_id>', methods=['PUT', 'DELETE'])
def savings_goal_detail(goal_id):
    """Pozwala edytować lub skasować wskazany cel oszczędnościowy."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    if not email:
        return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400

    updated_goal = None
    user_id = None
    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

        if request.method == 'DELETE':
            cursor.execute('DELETE FROM savings_goals WHERE id = ? AND user_id = ?', (goal_id, user_id))
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'Nie znaleziono celu.'}), 404
            conn.commit()
            return jsonify({'success': True, 'message': 'Cel usunięty.'})

        updates = {}
        if data.get('name') is not None:
            name = (data.get('name') or '').strip()
            if name:
                updates['name'] = name
        input_currency = normalize_currency(data.get('currency') or None)
        if data.get('target_amount') is not None:
            if input_currency is None:
                user = get_user_by_id(cursor, user_id)
                input_currency = normalize_currency(user['default_currency'] if user else None)
            updates['target_amount'] = convert_to_base(float(data.get('target_amount')), input_currency)
        if data.get('current_amount') is not None:
            if input_currency is None:
                user = get_user_by_id(cursor, user_id)
                input_currency = normalize_currency(user['default_currency'] if user else None)
            updates['current_amount'] = convert_to_base(float(data.get('current_amount')), input_currency)
        if data.get('deadline') is not None:
            updates['deadline'] = data.get('deadline') or None
        if data.get('category_id') is not None:
            updates['category_id'] = data.get('category_id')
        if data.get('is_active') is not None:
            updates['is_active'] = 1 if data.get('is_active') else 0

        if not updates:
            return jsonify({'success': False, 'message': 'Brak danych do aktualizacji.'}), 400

        set_parts = []
        params = []
        for key, value in updates.items():
            set_parts.append(f"{key} = ?")
            params.append(value)

        params.extend([goal_id, user_id])
        cursor.execute(
            f"UPDATE savings_goals SET {', '.join(set_parts)}, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?",
            params,
        )
        if cursor.rowcount == 0:
            return jsonify({'success': False, 'message': 'Nie znaleziono celu.'}), 404
        conn.commit()

    return jsonify({'success': True, 'message': 'Cel zaktualizowany.'})


@app.route('/savings-goals/<int:goal_id>/contributions', methods=['POST'])
def savings_goal_contribution(goal_id):
    """Dodaje wpłatę do celu, przeliczając kwotę do waluty bazowej."""
    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    amount = data.get('amount')
    currency = (data.get('currency') or '').strip().upper() if data.get('currency') else None
    if not email or amount is None:
        return jsonify({'success': False, 'message': 'Brak wymaganych danych.'}), 400
    if float(amount) <= 0:
        return jsonify({'success': False, 'message': 'Kwota musi być dodatnia.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

        cursor.execute('SELECT * FROM savings_goals WHERE id = ? AND user_id = ?', (goal_id, user_id))
        goal = cursor.fetchone()
        if not goal:
            return jsonify({'success': False, 'message': 'Nie znaleziono celu.'}), 404

        user = get_user_by_id(cursor, user_id)
        user_currency = normalize_currency(user['default_currency'] if user else None)
        contribution_currency = normalize_currency(currency or user_currency)
        converted_amount = convert_to_base(float(amount), contribution_currency)

        cursor.execute(
            'INSERT INTO savings_goal_contributions (goal_id, amount, note) VALUES (?, ?, ?)',
            (goal_id, converted_amount, data.get('note')),
        )
        conn.commit()

    return jsonify({'success': True, 'message': 'Wpłata dodana do celu.'})


@app.route('/dashboard/summary', methods=['GET'])
def dashboard_summary():
    """Liczy zagregowane dane finansowe na potrzeby pulpitu użytkownika."""
    email = request.args.get('email', '').strip().lower()
    period = request.args.get('period', 'monthly')
    if not email:
        return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400

    today = date.today()
    if period == 'weekly':
        start = (today - timedelta(days=today.weekday())).isoformat()
    elif period == 'monthly':
        start = today.replace(day=1).isoformat()
        end = request.args.get('end_date') or end_of_month(today).isoformat()
        start = today.replace(month=1, day=1).isoformat()
    else:
        start = request.args.get('start_date') or today.replace(day=1).isoformat()
    end = request.args.get('end_date') or today.isoformat()

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

    process_recurring_transactions(user_id)

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user = get_user_by_id(cursor, user_id)
        default_currency = normalize_currency(user['default_currency'] if user else None)

        cursor.execute(
            'SELECT COALESCE(SUM(COALESCE(converted_amount, amount)), 0) AS total_income FROM transactions WHERE user_id = ? AND type = ? AND occurred_on BETWEEN ? AND ?',
            (user_id, 'income', start, end),
        )
        total_income_base = cursor.fetchone()['total_income']

        cursor.execute(
            'SELECT COALESCE(SUM(COALESCE(converted_amount, amount)), 0) AS total_expense FROM transactions WHERE user_id = ? AND type = ? AND occurred_on BETWEEN ? AND ?',
            (user_id, 'expense', start, end),
        )
        total_expense_base = cursor.fetchone()['total_expense']

        cursor.execute(
            'SELECT c.name, COALESCE(SUM(COALESCE(t.converted_amount, t.amount)), 0) AS spent FROM transactions t LEFT JOIN categories c ON t.category_id = c.id '
            'WHERE t.user_id = ? AND t.type = ? AND t.occurred_on BETWEEN ? AND ? '
            'GROUP BY c.name ORDER BY spent DESC LIMIT 5',
            (user_id, 'expense', start, end),
        )
        top_categories = []
        for row in cursor.fetchall():
            entry = dict(row)
            entry['spent'] = convert_from_base(entry.get('spent') or 0, default_currency)
            top_categories.append(entry)

        cursor.execute(
            'SELECT limit_amount FROM budgets WHERE user_id = ? ORDER BY created_at DESC LIMIT 3',
            (user_id,),
        )
        recent_limits = [convert_from_base(row['limit_amount'], default_currency) for row in cursor.fetchall()]

    return jsonify({
        'success': True,
        'summary': {
            'period_start': start,
            'period_end': end,
            'total_income': convert_from_base(total_income_base, default_currency),
            'total_expense': convert_from_base(total_expense_base, default_currency),
            'net_savings': convert_from_base(total_income_base - total_expense_base, default_currency),
            'top_expense_categories': top_categories,
            'recent_budget_limits': recent_limits,
            'currency': default_currency,
        }
    })


@app.route('/reports/export', methods=['GET'])
def export_reports():
    """Buduje raport CSV z transakcjami w zadanym okresie i zwraca go jako plik."""
    email = request.args.get('email', '').strip().lower()
    start = request.args.get('start_date')
    end = request.args.get('end_date')
    if not email:
        return jsonify({'success': False, 'message': 'Brak adresu e-mail.'}), 400

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_id = resolve_user_id(cursor, email)
        if not user_id:
            return jsonify({'success': False, 'message': 'Nie znaleziono użytkownika.'}), 404

    process_recurring_transactions(user_id)

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user = get_user_by_id(cursor, user_id)
        default_currency = normalize_currency(user['default_currency'] if user and user['default_currency'] else None)

        query = (
            'SELECT t.occurred_on, t.type, t.amount, t.currency, t.converted_amount, t.note, c.name AS category_name '
            'FROM transactions t LEFT JOIN categories c ON t.category_id = c.id '
            'WHERE t.user_id = ?'
        )
        params = [user_id]
        if start:
            query += ' AND t.occurred_on >= ?'
            params.append(start)
        if end:
            query += ' AND t.occurred_on <= ?'
            params.append(end)
        query += ' ORDER BY t.occurred_on ASC, t.created_at ASC'

        cursor.execute(query, params)
        rows = cursor.fetchall()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Data', 'Typ', 'Kategoria', 'Kwota', 'Waluta', f'Kwota ({default_currency})', 'Notatka'])
    for row in rows:
        base_amount = row['converted_amount']
        if base_amount is None:
            base_amount = convert_to_base(float(row['amount']), normalize_currency(row['currency'] or default_currency))
        display_amount = convert_from_base(base_amount, default_currency)
        writer.writerow([
            row['occurred_on'],
            row['type'],
            row['category_name'] or '-',
            f"{row['amount']:.2f}",
            row['currency'] or default_currency,
            f"{display_amount:.2f}",
            row['note'] or '',
        ])

    csv_content = output.getvalue()
    filename = f"report_{date.today().isoformat()}.csv"
    response = make_response(csv_content)
    response.headers['Content-Disposition'] = f'attachment; filename={filename}'
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    return response


@app.route('/export/all', methods=['GET'])
@auth_required()
def export_all_data():
    """Eksportuje wszystkie dane zalogowanego użytkownika do jednego pliku CSV."""
    user = g.current_user
    user_id = user['id']

    process_recurring_transactions(user_id)

    with closing(get_db_connection()) as conn:
        cursor = conn.cursor()
        user_row = get_user_by_id(cursor, user_id)
        default_currency = normalize_currency(user_row['default_currency'] if user_row else None)

        cursor.execute('SELECT * FROM categories WHERE user_id = ? ORDER BY created_at ASC', (user_id,))
        categories = cursor.fetchall()

        cursor.execute('SELECT * FROM budget_types WHERE user_id = ? ORDER BY created_at ASC', (user_id,))
        budget_types = cursor.fetchall()

        cursor.execute('SELECT * FROM budgets WHERE user_id = ? ORDER BY created_at ASC', (user_id,))
        budgets = cursor.fetchall()

        cursor.execute('SELECT * FROM savings_goals WHERE user_id = ? ORDER BY created_at ASC', (user_id,))
        savings_goals = cursor.fetchall()

        cursor.execute(
            'SELECT * FROM savings_goal_contributions WHERE goal_id IN '
            '(SELECT id FROM savings_goals WHERE user_id = ?) ORDER BY created_at ASC',
            (user_id,),
        )
        goal_contributions = cursor.fetchall()

        cursor.execute('SELECT * FROM recurring_transactions WHERE user_id = ? ORDER BY created_at ASC', (user_id,))
        recurring = cursor.fetchall()

        cursor.execute(
            'SELECT t.*, c.name AS category_name, b.name AS budget_name '
            'FROM transactions t '
            'LEFT JOIN categories c ON t.category_id = c.id '
            'LEFT JOIN budgets b ON t.budget_id = b.id '
            'WHERE t.user_id = ? '
            'ORDER BY t.occurred_on ASC, t.created_at ASC',
            (user_id,),
        )
        transactions = cursor.fetchall()

    output = io.StringIO()
    writer = csv.writer(output)

    writer.writerow(['SEKCJA', 'użytkownik'])
    writer.writerow(['email', user.get('email')])
    writer.writerow(['display_name', user.get('display_name') or ''])
    writer.writerow(['default_currency', default_currency])
    monthly_income = user.get('monthly_income')
    monthly_income_currency = user.get('monthly_income_currency') or default_currency
    writer.writerow([
        'monthly_income',
        0 if monthly_income is None else monthly_income,
    ])
    writer.writerow(['monthly_income_currency', monthly_income_currency])
    writer.writerow(['monthly_income_day', user.get('monthly_income_day') or ''])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'kategorie'])
    writer.writerow(['id', 'name', 'type', 'color', 'icon_url', 'created_at'])
    for row in categories:
        writer.writerow([
            row['id'],
            row['name'],
            row['type'],
            row['color'] or '',
            row['icon_url'] or '',
            row['created_at'],
        ])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'typy_budzetow'])
    writer.writerow(['id', 'name', 'created_at'])
    for row in budget_types:
        writer.writerow([row['id'], row['name'], row['created_at']])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'budzety'])
    writer.writerow([
        'id',
        'name',
        'limit_amount',
        'period',
        'budget_type',
        'category_id',
        'start_date',
        'end_date',
        'created_at',
    ])
    for row in budgets:
        writer.writerow([
            row['id'],
            row['name'],
            convert_from_base(row['limit_amount'], default_currency),
            row['period'],
            row['budget_type'],
            row['category_id'] or '',
            row['start_date'] or '',
            row['end_date'] or '',
            row['created_at'],
        ])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'cele_oszczednosciowe'])
    writer.writerow([
        'id',
        'name',
        'target_amount',
        'current_amount',
        'deadline',
        'category_id',
        'is_active',
        'created_at',
        'updated_at',
    ])
    for row in savings_goals:
        writer.writerow([
            row['id'],
            row['name'],
            convert_from_base(row['target_amount'], default_currency),
            convert_from_base(row['current_amount'], default_currency),
            row['deadline'] or '',
            row['category_id'] or '',
            row['is_active'],
            row['created_at'],
            row['updated_at'],
        ])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'wplaty_do_celow'])
    writer.writerow(['id', 'goal_id', 'amount', 'note', 'created_at'])
    for row in goal_contributions:
        writer.writerow([
            row['id'],
            row['goal_id'],
            convert_from_base(row['amount'], default_currency),
            row['note'] or '',
            row['created_at'],
        ])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'transakcje_cykliczne'])
    writer.writerow([
        'id',
        'category_id',
        'type',
        'amount',
        'currency',
        'note',
        'frequency',
        'start_date',
        'next_occurrence',
        'end_date',
        'last_generated',
        'created_at',
    ])
    for row in recurring:
        writer.writerow([
            row['id'],
            row['category_id'] or '',
            row['type'],
            row['amount'],
            row['currency'] or default_currency,
            row['note'] or '',
            row['frequency'],
            row['start_date'],
            row['next_occurrence'],
            row['end_date'] or '',
            row['last_generated'] or '',
            row['created_at'],
        ])
    writer.writerow([])

    writer.writerow(['SEKCJA', 'transakcje'])
    writer.writerow([
        'id',
        'occurred_on',
        'type',
        'amount',
        'currency',
        f'converted_amount_{default_currency}',
        'category_id',
        'category_name',
        'budget_id',
        'budget_name',
        'note',
        'kind',
        'created_at',
    ])
    for row in transactions:
        writer.writerow([
            row['id'],
            row['occurred_on'],
            row['type'],
            f"{row['amount']:.2f}",
            row['currency'] or default_currency,
            f"{convert_from_base((row['converted_amount'] if row['converted_amount'] is not None else convert_to_base(float(row['amount']), normalize_currency(row['currency'] or default_currency))), default_currency):.2f}",
            row['category_id'] or '',
            row['category_name'] or '',
            row['budget_id'] or '',
            row['budget_name'] or '',
            row['note'] or '',
            row['kind'] or '',
            row['created_at'],
        ])

    csv_content = output.getvalue()
    filename = f"savoo_export_{date.today().isoformat()}.csv"
    response = make_response(csv_content)
    response.headers['Content-Disposition'] = f'attachment; filename={filename}'
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    return response


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5001)), debug=True)
