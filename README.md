# Audytor

Wersja **0.8.6+19**.

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
