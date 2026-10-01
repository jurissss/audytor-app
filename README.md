# Audytor

Wersja 0.8.2+15.

Najważniejsze funkcje:
- wyszukiwarka obiektów na ekranie głównym,
- lista ostatnich audytów na ekranie głównym,
- pełnoekranowy podgląd zdjęć z powiększaniem i przewijaniem,
- usterki ze zdjęciami,
- obowiązkowa tabliczka znamionowa albo oznaczenie jej braku,
- potwierdzenie usunięcia usterki z obowiązkowym komentarzem, datą i opcjonalnymi zdjęciami,
- raport PDF w układzie tabeli: Lp. / Pozycja / Nazwa urządzenia / Opis usterki / Zdjęcia,
- do 6 zdjęć przy każdej usterce w tabeli,
- wszystkie dalsze zdjęcia na automatycznych stronach kontynuacji,
- zdjęcia w PDF są osadzane osobno i zachowują oryginalne proporcje,
- orientacja EXIF zdjęć jest korygowana przed osadzeniem w PDF,
- bez kolumn SN i IoT,
- eksport i import paczki audytu.


Poprawka build #41:
- poprawione pozycjonowanie zdjęć w PDF dla pakietu pdf 3.11.x (bez nieobsługiwanych parametrów width/height w pw.Positioned).


## Wersja 0.8.2+15 – duże zdjęcia w PDF
- układ głównego raportu pozostaje bez zmian,
- każda miniatura w tabeli jest klikalna,
- kliknięcie miniatury przenosi do dużej wersji zdjęcia na końcu tego samego PDF,
- każde zdjęcie ma osobną stronę A4 i wysoką rozdzielczość do powiększania,
- na stronie dużego zdjęcia jest link „Powrót do usterki”,
- dokumentacja działa bez internetu i bez Google Drive.
