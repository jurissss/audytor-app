# Audytor

Wersja 0.8.3+16.

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


## 0.8.3+16 – dynamiczne dzielenie dużych raportów
- limit jednej części PDF: 23 MB,
- podział zawsze na granicy całej usterki,
- każda część ma tabelę z miniaturami oraz duże zdjęcia swoich usterek,
- zdjęcia duże są dynamicznie kompresowane do ok. 250 kB,
- miniatury są kompresowane do ok. 48 kB,
- rzeczywisty rozmiar PDF jest sprawdzany po wygenerowaniu,
- gdy część przekracza limit, ostatnia usterka przechodzi do następnego PDF,
- przy kilku częściach aplikacja pozwala udostępnić wszystkie PDF-y jednocześnie.
