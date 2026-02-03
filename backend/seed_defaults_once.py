"""Jednorazowo dosiewa domyślne kategorie dla istniejących użytkowników."""
from contextlib import closing
from typing import List

import savoo_api


def _collect_user_ids() -> List[int]:
    """Zwraca listę identyfikatorów wszystkich użytkowników zapisanych w bazie."""
    with closing(savoo_api.get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT id FROM users ORDER BY id ASC')
        return [row['id'] for row in cursor.fetchall()]


def seed_all_users() -> None:
    """Dla każdego użytkownika w bazie wywołuje funkcje dosiewające dane startowe."""
    savoo_api.init_db()
    savoo_api.migrate_db()
    user_ids = _collect_user_ids()
    if not user_ids:
        print('Brak użytkowników do aktualizacji.')
        return

    total_categories = 0
    for user_id in user_ids:
        before_categories = _count_categories(user_id)
        savoo_api.seed_default_categories(user_id)
        total_categories += _count_categories(user_id) - before_categories

    print(f'Zaktualizowano {len(user_ids)} kont. Dodano {total_categories} kategorii.')


def _count_categories(user_id: int) -> int:
    """Pomocniczo zlicza kategorie należące do wskazanego użytkownika."""
    with closing(savoo_api.get_db_connection()) as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) AS total FROM categories WHERE user_id = ?', (user_id,))
        return cursor.fetchone()['total']


if __name__ == '__main__':
    seed_all_users()
