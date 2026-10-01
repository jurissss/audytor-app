# Audytor

Wersja **0.9.1+24**.

## Najważniejsze zmiany

- moduł **Obiekty** został usunięty z interfejsu,
- każdy audyt jest samodzielny i zawiera:
  - Klient,
  - Numer sklepu,
  - Adres,
  - Audytor,
- ostatnio wpisany **Audytor** jest zapamiętywany i automatycznie podpowiadany,
- istniejące audyty są migrowane: nazwa/kod/adres starego obiektu trafiają bezpośrednio do audytu,
- po zakończeniu audytu przy nieusuniętej usterce dostępne są:
  - **Potwierdź usunięcie**,
  - **Dodaj uwagę**,
- uwaga może zawierać komentarz, zdjęcia albo oba elementy,
- kolejne uwagi tworzą historię z datą i zdjęciami,
- historia uwag jest uwzględniana w raporcie PDF i w paczce eksportowej,
- raport zachowuje układ 8 usterek na stronie i 5 miniatur w jednym rzędzie,
- duże zdjęcia mają link **Powrót do usterki** u góry i na dole,
- pozostaje szybkie generowanie, kompresja zdjęć do ok. 250 kB oraz dynamiczny podział PDF do ok. 23 MB bez rozdzielania jednej usterki.

## Poprawka 0.8.7+20 – uwagi w PDF
- uwaga ze zdjęciem nie tworzy już osobnej dodatkowej strony historii,
- zdjęcie uwagi ma tylko swoją właściwą stronę zdjęciową,
- na stronie zdjęcia uwagi pokazuje się data i treść uwagi,
- osobna strona „Uwagi tekstowe” powstaje tylko dla uwag bez zdjęć.

## 0.8.8+21 – bardziej zwarta lista usterek
- karty usterek mają mniejsze odstępy i padding,
- miniatury na liście są mniejsze,
- historia uwag jest domyślnie zwinięta i rozwijana na żądanie,
- przyciski „Potwierdź usunięcie” i „Dodaj uwagę” są bardziej kompaktowe,
- w formularzu nowego audytu dodano pole „Typ audytu”,
- typ audytu jest widoczny także w nagłówku audytu i na liście audytów.

## 0.8.9+22 – stały przycisk zapisu usterki
- przycisk „Zapisz usterkę” jest stale widoczny jako pływający przycisk,
- podczas edycji pokazuje „Zapisz zmiany”,
- nie trzeba przewijać formularza na sam dół,
- dolna część formularza ma dodatkowy margines, żeby przycisk nie zasłaniał pól.

## 0.9.0+23 – bardziej kompaktowa edycja usterki
- pole „Opis usterki” zmniejszone mniej więcej o połowę,
- pole „Zalecenie / sposób naprawy” przemianowane na „Uwagi”,
- „Uwagi” ograniczone do jednej linii.

## 0.9.1+24 – prawdziwy zapis PDF
- usunięto mylący przycisk „Drukuj / zapisz jako PDF”,
- dodano osobny przycisk „Zapisz PDF w Pobranych”,
- zapis korzysta z systemowego okna zapisu Androida,
- w oknie można wybrać folder „Pobrane” i zapisać gotowy plik PDF,
- drukowanie pozostaje jako osobna funkcja „Drukuj”,
- przy raporcie podzielonym na części każdą część można osobno zapisać albo wydrukować.
