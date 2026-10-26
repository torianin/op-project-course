# Fat Angel Multiplayer

Przeglądarkowa gra multiplayer: latające anioły, strzelanie sercami i wspólny czat.
Serwer w Ruby utrzymuje jeden pokój; przeglądarka rysuje rozgrywkę na Canvas.

**Zagraj:** [fat-angel.onrender.com](https://fat-angel.onrender.com)

## Jak zacząć

1. Otwórz grę w przeglądarce z klawiaturą i myszą.
2. Wpisz nick mający **2–30 znaków** po usunięciu spacji z początku i końca.
3. Dołączysz do wspólnego pokoju, który mieści **do 25 graczy**.
4. Zaproś drugą osobę pod ten sam adres albo otwórz grę w drugim oknie.

Anulowanie pytania o nick zamyka połączenie. Po utracie połączenia odśwież stronę,
aby dołączyć ponownie; klient nie wznawia sesji automatycznie.

## Zrzuty ekranu

Zrzuty pochodzą z publicznej wersji gry uruchomionej w Safari i obejmują obszar rozgrywki.

### Rozgrywka

![Zrzut rozgrywki Fat Angel Multiplayer](docs/screenshots/rozgrywka.png)

Własna postać, licznik trafień, minimapa i bonus w świecie gry.

### Multiplayer i czat

![Zrzut multiplayera i czatu Fat Angel Multiplayer](docs/screenshots/multiplayer-czat.png)

Dwie niezależne sesje — „Aniolek” i „Amorek” — oraz wiadomość wspólnego czatu.

## Co można robić

- **Latać z bezwładnością.** Ruch poziomy utrzymuje się po puszczeniu klawisza,
  a przyspieszanie i opadanie wynikają z prostego modelu fizyki na serwerze.
- **Strzelać sercami** w stronę kursora. Każdy gracz ma jeden aktywny pocisk;
  następny strzał zastępuje poprzedni.
- **Trafiać innych graczy.** Trafienie zwiększa wynik strzelającego o punkt.
  Trafiony anioł rośnie o 10 pikseli w obu wymiarach, od 100×100 do 150×150,
  i pojawia się w losowym miejscu. Trafienie nie eliminuje gracza.
- **Sprawdzać wyniki.** Lista nicków i liczby trafień jest widoczna podczas gry.
- **Zbierać bonus „Ciężka miłość”.** Zebranie zatrzymuje ruch poziomy,
  a następne ruchy w lewo lub prawo mają ograniczoną prędkość.
  Efekt znika losowo podczas aktualizacji świata.
- **Rozmawiać na wspólnym czacie.** Wiadomości trafiają do wszystkich
  aktualnie połączonych graczy; serwer przyjmuje wiadomości do 500 znaków.

Kamera podąża za własną postacią. Świat ma powtarzane tło, animowane sprite'y
aniołów i nicki przy postaciach. Uproszczona minimapa oznacza własnego gracza,
pozostałych graczy oraz bonusy: własny znacznik jest czerwony, inni gracze
są oznaczeni na złoto, a bonusy na brązowoczerwono.

## Sterowanie

| Klawisz / gest | Działanie |
| --- | --- |
| **A** | Rozpędzanie w lewo |
| **D** | Rozpędzanie w prawo |
| **W** | Zmiana ruchu pionowego w górę, przeciwdziałanie opadaniu |
| **S** | Zatrzymanie ruchu poziomego |
| **R** | Losowa zmiana pozycji i zatrzymanie ruchu poziomego |
| **Kliknięcie myszy** | Strzał w stronę kursora, przy puszczeniu przycisku |
| **T** | Otwarcie okna wpisywania wiadomości czatu |
| **Przytrzymanie myszy ponad 2 s** | Przy puszczeniu: okno czatu, a potem strzał |

Po długim przytrzymaniu przycisku strzał następuje także po anulowaniu okna czatu.
Klawisz **R** zachowuje rozmiar postaci, zdobyte punkty, bonus i istniejący pocisk.

## Zakres i ograniczenia

- Jest jeden wspólny pokój, bez wyboru serwera, prywatnych lobby i drużyn.
- Świat nie ma ścian ani podłoża; nie ma również punktów życia, eliminacji
  ani końca rundy.
- Nie ma kont, logowania ani zapisu postępu; nick jest nazwą bieżącej sesji.
- Wyniki i cały świat istnieją wyłącznie w pamięci jednego procesu.
  Restart, wdrożenie lub uśpienie usługi zeruje pokój i rozłącza graczy.
- Uruchamiaj **jedną instancję i jeden proces**; instancje nie dzielą stanu gry.
- Klient pobiera stan do około 30 razy na sekundę. Symulacja postępuje przy
  żądaniach stanu, bez niezależnego, stałego zegara gry.
- Nie ma automatycznego ponownego łączenia ani przywracania poprzedniej sesji.
- Obsługa gamepada ma puste callbacki. Nie ma ekranowych przycisków ruchu
  ani kompletnego sterowania dotykowego; podstawowy interfejs to klawiatura i mysz.

## Architektura i pliki

HTTP i WebSocket używają tego samego procesu Thin i tego samego portu.
Sinatra serwuje stronę i zasoby, a Faye WebSocket obsługuje połączenia pod `/ws`.
Pozycje, pociski, trafienia, bonusy i wyniki wylicza serwer.
Klient wybiera `ws://` lub `wss://` zgodnie z protokołem otwartej strony.

```text
server.rb                   model gry, HTTP, WebSocket i start serwera
config.ru                   wejście Rack dla WebSocketApp
views/index.erb             strona gry
views/application.coffee    źródło klienta w CoffeeScript
public/application.js       gotowy klient JavaScript serwowany przeglądarce
public/js/                  lokalne biblioteki CanvasQuery, jQuery i Alertify
public/img/                 postacie, tło, pociski i bonusy
public/css/                 style gry i powiadomień
scripts/compile-client.js   kompilacja klienta
scripts/smoke-test.mjs      test HTTP i multiplayera
docs/screenshots/           zrzuty użyte w dokumentacji
Dockerfile                  obraz aplikacji
render.yaml                 alternatywna konfiguracja Render Blueprint
```

## Uruchomienie lokalne

Potrzebne są Ruby **3.3**, Bundler **2.5.22**, kompilator C/C++, `make`
i nagłówki OpenSSL do zbudowania gemów natywnych.

```sh
gem install bundler -v 2.5.22
bundle install
bundle exec ruby server.rb
```

Otwórz [localhost:8080](http://localhost:8080). Ten sam serwer udostępnia grę,
grafiki i WebSocket; nie trzeba uruchamiać oddzielnego serwera frontendu.

| Zmienna | Wartość domyślna | Znaczenie |
| --- | --- | --- |
| `PORT` | `8080` | Port HTTP i WebSocket |
| `BIND` | `0.0.0.0` | Adres nasłuchiwania |
| `RACK_ENV` | `production` | Środowisko Sinatry |

Przykład: `BIND=127.0.0.1 PORT=9090 bundle exec ruby server.rb`.

### Docker

```sh
docker build --pull -t fat-angel .
docker run --rm -p 8080:8080 fat-angel
```

Obraz używa Ruby 3.3 na Debianie Bookworm. Gemy natywne powstają w osobnym
etapie budowania, a aplikacja działa jako użytkownik bez uprawnień roota.
Node.js nie jest wymagany w kontenerze ani do zwykłego uruchomienia serwera.

### Zmiana klienta i szybka weryfikacja

Do poniższych skryptów użyj Node.js 24. Po edycji CoffeeScript przebuduj
i zapisz w repozytorium również wygenerowany `public/application.js`:

```sh
node scripts/compile-client.js
```

Skrypt korzysta z zapisanego w repozytorium kompilatora CoffeeScript 1.6.2.
Przy działającym serwerze uruchom test lokalny albo wskaż publiczny adres:

```sh
node scripts/smoke-test.mjs
node scripts/smoke-test.mjs https://fat-angel.onrender.com
```

Test sprawdza stronę, `/healthz`, zasoby i dwóch tymczasowych graczy:
nicki, wspólny stan, ruch, strzały, czat i usunięcie gracza po rozłączeniu.
Na końcu zamyka swoje połączenia.

## HTTP i minimalny protokół WebSocket

| Adres | Funkcja |
| --- | --- |
| `GET /` | Strona gry |
| `GET /application.js` | Skompilowany klient |
| `GET /img/*`, `/js/*`, `/css/*` | Zasoby statyczne |
| `GET /healthz` | JSON, np. `{"status":"ok","players":2}` |
| `/ws` | Połączenie WebSocket; zwykłe HTTP zwraca `426` |

Wiadomości klienta są tekstowe, bez otoczki JSON:

| Klient → serwer | Znaczenie |
| --- | --- |
| `i` | Pobierz identyfikator własnego gracza |
| `nAla` | Ustaw nick `Ala` |
| `j` | Pobierz aktualny stan świata |
| `l`, `r`, `t`, `b` | Ruch w lewo, w prawo, w górę, zatrzymanie poziome |
| `q` | Reset pozycji i ruchu |
| `p100.5,200` | Strzel w kierunku wskazanego punktu świata |
| `mCześć!` | Wyślij wiadomość czatu |

Serwer odpowiada `i:<id>` i `j:<JSON>`. Stan zawiera tablice `id`, `name`,
`coordinates`, `sizes`, `rotates`, `frames` i `shooted` w kolejności graczy
oraz osobne tablice `bullets` i `bonuses`. Czat przychodzi jako `nick: wiadomość`,
a komunikat o bonusie jako tekst `Ciężka miłość`.
Przepełniony pokój zamyka nowe połączenie kodem `4008` (`Room full`).

## Wdrożenie na Render

Publiczna usługa została utworzona bezpośrednio z repozytorium
`torianin/op-project-course`, brancha `codex/ai-fun`, jako pojedynczy Docker
w regionie Frankfurt na planie `free`. Automatyczne wdrożenia są wyłączone.
Kolejne wdrożenie wymaga ręcznego uruchomienia po wypchnięciu zmian.

Obecna usługa korzysta z kontroli portu TCP: jej `healthCheckPath` jest pusty.
Endpoint HTTP `/healthz` działa i można go wskazać osobno w ustawieniach.
Plik `render.yaml` jest alternatywą do utworzenia usługi przez Blueprint;
w tej konfiguracji ścieżka `/healthz` jest już zadeklarowana.

Render przekazuje `PORT` i zapewnia publiczne HTTPS oraz `wss://` pod `/ws`.
Plan `free` usypia usługę po 15 minutach bez przychodzącego ruchu HTTP lub
wiadomości WebSocket; ponowne uruchomienie zwykle trwa około minuty.
Szczegóły: [limity planu free](https://render.com/docs/free)
i [referencja Blueprint](https://render.com/docs/blueprint-spec).
