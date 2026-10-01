# Audytor

Wersja 0.8.0+12.

Najważniejsze funkcje:
- ekran główny z wyszukiwarką obiektów,
- lista ostatnich audytów na ekranie głównym,
- bezpośrednie otwieranie audytu z ekranu głównego,
- obiekty i audyty,
- usterki ze zdjęciami,
- obowiązkowa tabliczka znamionowa albo oznaczenie jej braku,
- potwierdzenie usunięcia usterki z obowiązkowym komentarzem, datą i opcjonalnymi zdjęciami,
- klikalne miniatury zdjęć w aplikacji,
- pełnoekranowy podgląd zdjęć z powiększaniem i przewijaniem,
- raport PDF w układzie tabeli podobnym do raportu referencyjnego,
- kolumny raportu: Lp., Pozycja, Nazwa urządzenia, Opis usterki, Zdjęcia,
- brak kolumn SN i Nr IoT,
- do 4 usterek na stronie raportu,
- zdjęcia w PDF zachowują proporcje,
- wszystkie dodatkowe zdjęcia są dodawane na dalszych stronach PDF,
- ponowne generowanie raportu po potwierdzeniu napraw,
- eksport paczki audytu z PDF, galerią HTML, manifestem i skompresowanymi zdjęciami,
- import paczki na innym urządzeniu w celu weryfikacji / reaudytu.

## Google Drive

Przycisk „Udostępnij PDF” korzysta z systemowego menu Androida, więc PDF można zapisać także do aplikacji Dysk Google, jeśli jest zainstalowana. Automatyczne utworzenie folderu na Google Drive oraz wygenerowanie publicznego linku wymaga osobnej konfiguracji OAuth / Google Drive API i nie jest jeszcze częścią tej wersji.
