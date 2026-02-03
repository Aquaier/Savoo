# Savoo – domowe finanse

Savoo to aplikacja do zarządzania budżetem domowym. Projekt składa się z aplikacji Flutter oraz backendu Flask opartego na SQLite. Dane użytkownika są przechowywane lokalnie w bazie `savoo.db` i udostępniane przez REST API.

## Najważniejsze możliwości

- szybkie logowanie i rejestracja konta
- dashboard z podsumowaniem miesiąca i listą najczęstszych kategorii
- obsługa transakcji (przychody, wydatki, transfery)
- budżety miesięczne/tygodniowe/kwartalne
- cele oszczędnościowe i wpłaty na cele
- transakcje cykliczne (ustalenie dnia, w którym wypłacane jest nam wynagrodzenie)
- obsługa wielu walut + przeliczanie kwot
- eksport danych użytkownika do CSV

## Ekrany i przepływ

1. Logowanie/Rejestracja – podstawowe dane + pytanie bezpieczeństwa do resetu hasła.
2. Pulpit – bilans miesiąca, szybkie karty i skróty.
3. Transakcje – lista operacji i dodawanie nowych wpisów.
4. Cele – zarządzanie oszczędnościami i wpłatami.
5. Budżety – lista limitów, szczegóły i wykresy.
6. Profil – edycja danych użytkownika, ustawienie dnia wypłaty, eksport CSV.

## Backend (Flask)

1. Zainstaluj zależności:
	```bash
	cd backend
	pip install -r requirements.txt
	```
2. Uruchom serwer:
	```bash
	python savoo_api.py
	```
	API startuje na `http://localhost:5001`, tworzy plik `savoo.db`.

## Frontend (Flutter)

1. Zainstaluj pakiety:
	```bash
	flutter pub get
	```
2. Uruchom aplikację:
	```bash
	flutter run
	```

## Uruchomienie na emulatorze Android (Visual Studio Code + Android Studio)

Poniższe kroki prowadzą od instalacji narzędzi do uruchomienia aplikacji na emulatorze Android.

### 1) Instalacja Android Studio i narzędzi Android

1. Pobierz i zainstaluj Android Studio ze strony producenta.
2. Uruchom Android Studio i przejdź przez kreator pierwszej konfiguracji.
3. W kreatorze wybierz instalację narzędzi Android, w tym:
	- Zestaw narzędzi programistycznych Android (Android Software Development Kit).
	- Emulator Android.
	- Narzędzia platformy (Android Platform Tools).
	- Przynajmniej jedną platformę systemu Android (na przykład Android 13).

### 2) Utworzenie i uruchomienie urządzenia wirtualnego

1. W Android Studio otwórz menu **Tools → Device Manager**.
2. Kliknij **Create Device**.
3. Wybierz model telefonu (na przykład Pixel 6) i kliknij **Next**.
4. Wybierz obraz systemu Android (zalecane są obrazy z oznaczeniem Google APIs).
5. Kliknij **Download**, poczekaj na pobranie i kliknij **Next**.
6. Zatwierdź ustawienia i kliknij **Finish**.
7. W Device Manager kliknij przycisk **Play** przy nowo utworzonym urządzeniu.
8. Poczekaj aż emulator w pełni się uruchomi i pokaże ekran główny.

### 3) Instalacja Visual Studio Code i rozszerzeń

1. Zainstaluj Visual Studio Code.
2. W Visual Studio Code otwórz panel rozszerzeń.
3. Zainstaluj rozszerzenia o nazwach **Flutter** oraz **Dart**.

### 4) Sprawdzenie środowiska Flutter

1. Otwórz terminal w Visual Studio Code w katalogu projektu.
2. Wykonaj polecenie:
	```bash
	flutter doctor
	```
3. Jeśli narzędzia Android nie są wykrywane, ustaw zmienne środowiskowe:
	- `ANDROID_HOME` jako ścieżkę do folderu Android Software Development Kit.
	- dodaj folder `platform-tools` do zmiennej środowiskowej `PATH`.
4. Zamknij i ponownie otwórz Visual Studio Code, aby zmiany środowiskowe zostały wczytane.

### 5) Uruchomienie backendu

1. Otwórz nowy terminal w Visual Studio Code.
2. Przejdź do folderu backend:
	```bash
	cd backend
	```
3. Zainstaluj wymagane pakiety Python:
	```bash
	pip install -r requirements.txt
	```
4. Uruchom serwer backendu:
	```bash
	python savoo_api.py
	```
5. Pozostaw ten terminal otwarty.

### 6) Uruchomienie aplikacji na emulatorze

1. Upewnij się, że emulator jest uruchomiony.
2. W Visual Studio Code, na pasku stanu, kliknij nazwę urządzenia (lub napis **No Device**) i wybierz uruchomiony emulator.
3. W terminalu uruchom aplikację:
	```bash
	flutter run
	```

## Eksport CSV

Eksport działa dla aktualnie zalogowanego użytkownika i zapisuje pełny pakiet danych (transakcje, budżety, kategorie, cele, cykliczne) do pliku CSV. Na Androidzie plik trafia do katalogu „Pobrane”.

## Struktura projektu

- `backend/` – Flask API + SQLite
- `lib/` – aplikacja Flutter (UI, stan, integracja API)

## Wymagania

- Python 3.10+
- Flutter 3.x
