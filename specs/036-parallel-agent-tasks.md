# 036 — Równoległe zadania na jednym agencie

Status: **draft** (do przeglądu właściciela)
Date: 2026-11-21
Depends on: [009](009-agents.md), [010](010-task-execution.md), [016](016-sequential-steps.md), [018](018-working-folders.md), [023](023-agent-status.md), [032](032-automatic-step-retry.md)

## 1. TL;DR

Jeden agent może wykonywać domyślnie sześć zadań równocześnie, również w różnych przestrzeniach. Status pokazuje obciążenie, np. „3/6 w toku”, a nadmiarowe zadania czekają na miejsce. Test odbiorczy sprawdza sześć nakładających się wykonań w niezależnych katalogach i automatyczny start siódmego po zwolnieniu miejsca. Agent nie ma własnego katalogu: pracuje w katalogu przestrzeni, a kroki dzielące jeden katalog przestrzeni idą po kolei.

## 2. Abstract

Scheduler ma dwa wspólne wątki wykonawcze na proces. Z tej samej kolejki korzystają kroki epików, zadania kalendarzowe i przebiegi dyrektora. Jeden agent już może wykonywać kroki różnych epików, a spec 016 utrzymuje sekwencyjność kroków pojedynczego epiku. Status ze spec 023 pokazuje aktywność widoczną dla konta, więc lista widocznych kroków stanowi tylko część obciążenia wykonawczego. CLI może dziś pracować bezpośrednio we wspólnym katalogu projektu. Większa równoległość wymaga rozdzielenia katalogów roboczych oraz pojemności workerów i obu pul połączeń SQLite.

## 3. Objective

**Cele**

- G1. Umożliwić ustawienie limitu osobno dla każdego agenta i egzekwować go przy starcie zadania.
- G2. Pokazywać wykorzystanie limitu i przepuszczać oczekujące zadania po zwolnieniu miejsca.
- G3. Nie dopuścić, by równoległe próby pracowały w tym samym katalogu, i zwiększyć pojemność wykonawczą wraz z limitem.

**Poza zakresem**

- Równoległe kroki tego samego epiku, limity poszczególnych executorów, uruchamianie schedulera w wielu procesach oraz automatyczne scalanie zmian w projekcie.

**Kryteria akceptacji**

- S1. Nowy i istniejący agent bez własnej wartości mają limit 6. Uprawniony edytor może zapisać liczby całkowite od 1 do 10. Odrzucony zapis zachowuje dotychczasowy limit.
- S2. Sześć kwalifikujących się zadań jednego agenta z co najmniej dwóch przestrzeni wykonuje się jednocześnie. Siódme czeka bez zajmowania workera i rusza po zwolnieniu miejsca, także po błędzie. W tym czasie scheduler może przyjąć kwalifikującą się pracę innego agenta, gdy ma wolny worker.
- S3. Status odzwierciedla zajęte sloty, np. „3/6 w toku” przy dostępnej pojemności i „6/6 w toku” ze statusem zajęty. Obniżenie limitu do 2 przy trzech aktywnych zadaniach pokazuje „3/2 w toku” i blokuje start do chwili, gdy zostanie mniej niż 2.
- S4. Dwie równoległe próby bez katalogu przestrzeni zapisują plik o tej samej nazwie bez wzajemnego nadpisania. Próba ponowienia otrzymuje własny katalog. Kroki przestrzeni z różnymi katalogami roboczymi wykonują się równocześnie. Kroki przestrzeni wskazujących ten sam katalog, także przez dowiązanie, wykonują się w nim po kolei.
- S5. Po restarcie wpisy oczekujące wracają do kolejki, a przerwane próby zwalniają sloty zgodnie z R5. Przy limicie 10 test z kontrolowanym executorem potwierdza 10 aktywnych przebiegów i obsługę żądań HTTP oraz zapisów audytu bez wyczerpania pul połączeń.

- S6. Każdy uprawniony użytkownik współdzielonego agenta widzi tę samą łączną liczbę zadań w toku i limit, także gdy zadania należą do innych kont lub przestrzeni. Szczegóły aktywności są widoczne zgodnie z dotychczasowymi uprawnieniami. Konto bez dostępu do agenta nie otrzymuje licznika.

## 4. Artefact Inventory

| Obszar | Element | Stan |
|---|---|---|
| Dane | Konfiguracja agenta i walidacja limitu | do zmiany |
| System | Kolejka, atomowe przejęcie przebiegu i odzyskiwanie po restarcie | do zmiany |
| System | Status agenta na stronie zespołu, w pasku czatu i w kontekście planowania | do zmiany |
| System | Katalog próby i kolejność kroków we wspólnym katalogu przestrzeni | do zmiany |
| System | Pula workerów oraz pule baz primary i audit | do zmiany |
| System | Testy limitu, kolejki, izolacji i restartu | do utworzenia |

## 5. Functional Domain Changes

- **Stan.** Dwa wspólne wątki i status aktywności przechodzą w przydział ograniczony pojemnością agenta i status wykorzystania limitu.
- **R1.** Limit zapisuje osoba uprawniona do edycji agenta według spec 009. Wartość domyślna to 6, dopuszczalny zakres to 1–10. Jednostką jest wykonywana próba kroku epiku lub zadania kalendarzowego przypisana do agenta. Czat, planowanie oraz weryfikacja w odrębnej roli korzystają z własnych reguł dopuszczania.
- **R2.** Wszystkie objęte limitem próby danego agenta zajmują wspólną pojemność według jego identyfikatora, niezależnie od przestrzeni i konta. Sprawdzenie pojemności i przejęcie wpisu z kolejki są atomowe. Oczekujące wpisy pozostają w stanie `queued`. Scheduler wybiera najstarszy kwalifikujący się wpis według kolejności przyjęcia i może ominąć wpis blokowany przez wyczerpany limit agenta.
- **R3.** Slot zajmuje stan `running`. Status „zajęty” obowiązuje przy liczniku równym limitowi lub wyższym. Szczegóły aktywności podlegają uprawnieniom konta i przestrzeni. Każdy uprawniony użytkownik agenta widzi łączną liczbę jego wykonywanych zadań i jego limit.
- **R4.** Zapis limitu obejmuje kolejne decyzje o starcie. Podwyższenie pozwala uruchomić oczekujące próby przy dostępnych workerach. Po obniżeniu próby już uruchomione dobiegają końca. Start kolejnej jest możliwy po zejściu poniżej nowego limitu.
- **R5.** Zakończenie sukcesem, błędem, anulowaniem lub przekroczeniem czasu zwalnia slot po zakończeniu wykonania i zapisie stanu końcowego. Ponowienie podlega regułom kolejki i spec 032. Po restarcie scheduler przed przydziałem slotów rozlicza przerwane próby jako błędy według reguł odzyskiwania. Wznowienie kolejki zachowuje zapisane wpisy i wyklucza podwójne wykonanie tej samej próby. Jeżeli poprzedni proces executora przetrwał restart, odzyskiwanie musi potwierdzić jego zakończenie przed zwolnieniem slotu.
- **R6.** Agent nie ma własnego stałego katalogu (decyzja właściciela). Krok przestrzeni z katalogiem roboczym pracuje w katalogu tej przestrzeni według spec 018, bez kopii projektu. Każda inna próba, także ponowienie, dostaje własny katalog przebiegu `var/runs/<env>/<id>`. W jednym katalogu przestrzeni, rozpoznanym po ścieżce rzeczywistej (także przez dowiązanie), pracuje naraz najwyżej jeden krok. Kolejny czeka w kolejce bez zajmowania workera i bez zajmowania slotu agenta. Kroki przestrzeni z różnymi katalogami wykonują się równolegle w granicach limitu. Brak katalogu przestrzeni kończy próbę błędem i zwalnia slot.
- **R7.** Wspólna pula workerów skaluje się wraz z najwyższym skonfigurowanym limitem aktywnych agentów i zapewnia pojemność na osiągnięcie tego limitu przez jednego agenta. Zwiększenie pojemności obowiązuje bez restartu. Pule `primary` i `audit` uwzględniają workery oraz zapas na wątki HTTP, scheduler i pamięć. Zmniejszenie pojemności czeka na zakończenie aktywnych wykonań. Łączna pula pozostaje współdzielona.
- **Dane.** Istniejące rekordy otrzymują efektywną wartość 6. Zapisane stany przebiegów są źródłem odtworzenia kolejki i obciążenia. Rozliczanie przerwanych prób weryfikuje stan faktycznego wykonania.

## 6. Critical Path

1. Zamknąć specyfikację po przeglądzie właściciela. Zdefiniować walidację i domyślną wartość dla istniejących agentów.
2. Spiąć przydział slotów z trwałą kolejką, zakończeniem i odzyskiwaniem. Dostosować workery i obie pule połączeń.
3. Rozdzielić katalogi prób według R6 i podłączyć status do tego samego stanu, który rozstrzyga o przydziale.
4. Przejść bramki z sekcji 7, przeprowadzić analizę bezpieczeństwa B20 oraz zweryfikować README i CHANGELOG względem kodu i testów.

## 7. Control Gates

| Bramka | Warunek zaliczenia | Weryfikacja | Blokuje | Bramka negatywna |
|---|---|---|---|---|
| Unit | S1 i stany S3 | Test ustawień, licznika i progu | Integrację | Odrzucone 0, 11 i ułamek, brak slotu dla wpisu `queued` |
| Integration | S2 oraz R4–R5 | Test z barierą synchronizującą jednoczesne próby przejęcia, zmianą limitu w górę i w dół, błędem i restartem | Odbiór | Nadmiarowy start, podwójne przejęcie, utrata kolejki lub osierocony slot |
| Contract | S4 i R6 | Test przydziału dla przestrzeni z różnymi i wspólnymi katalogami oraz test zapisu dwóch prób | Odbiór | Dwa kroki naraz w jednym katalogu, także przez dowiązanie; wstrzymanie kroków z różnych katalogów; nadpisanie pliku innej próby |
| E2E | S3, S5 i S6 | Test interfejsu oraz próba współbieżności z zapisem w obu bazach i ruchem HTTP | Wydanie | Rozbieżność statusu i przydziału, ujawnienie szczegółów poza uprawnieniami, wyczerpanie puli |
| Manual | Czytelny status oraz reguły widoczności z S6 | Przejście na kontach z różnymi uprawnieniami i kontrolowany restart | Wydanie | Ujawnienie szczegółów cudzej aktywności lub błędny licznik po odtworzeniu kolejki |

## 8. Expected Outcome

- **Efekt bezpośredni.** Agent przyjmuje zadania z kilku przestrzeni zgodnie ze swoją pojemnością.
- **Efekt mierzalny.** Sześć nakładających się wykonań przy ustawieniach domyślnych oraz dziesięć przy maksymalnym limicie w próbie z kontrolowanym executorem.
- **Skutki uboczne.** Rosną potrzeby CPU, pamięci, miejsca na dysku i przepustowości executora. SQLite nadal szereguje zapisy.
- **Wycofanie.** Operacyjne zmniejszenie limitu do 1 pozwala aktywnym próbom dobiec końca. Wycofanie wdrożenia wymaga zatrzymania przydziału i rozliczenia aktywnych prób przy zachowaniu zapisanej kolejki.

## 9. Additional Information

- **Odrzucone alternatywy.** Samo zwiększenie wspólnej puli workerów pomija limit per agent. Kopia projektu lub `git worktree` dla każdej próby — odrzucone przez właściciela: agent pracuje w katalogu przestrzeni. Równoległe kroki w jednym katalogu przestrzeni — ryzyko kolizji plików i indeksu Git.
- **Dług techniczny.** Wspólna kolejka może opóźniać pracę dyrektora pod pełnym obciążeniem. Osobna rezerwa workerów dla dyrektora jest poza zakresem.
- **Zależności zewnętrzne.** Osiągalna równoległość zależy od sprzętu i pojemności executora.
- **Decyzja właściciela (R6).** „Agent działa w przestrzeni na określonym katalogu, agent nie ma swojego stałego katalogu”. Katalog należy do przestrzeni, więc równoległość dotyczy zadań z różnych przestrzeni; zadania jednej przestrzeni z katalogiem idą po kolei.
- **Źródła.** Raport „Analiza: co dziś ogranicza równoległość” z kroku 1 epiku oraz [scheduler](../lib/agentaro/task_scheduler.rb), [status](../app/models/agent_status.rb), [wykonanie](../app/models/agent_call.rb) i [konfiguracja baz](../config/database.yml).
- **Decyzja właściciela.** Każdy uprawniony użytkownik agenta widzi łączne obciążenie, także gdy obejmuje zadania, do których szczegółów nie ma dostępu. Zmiana licznika ujawnia zmianę łącznego obciążenia.
- **Stan wdrożenia (2026-11-21, krok 3 epiku).** Backend R1–R7 jest wdrożony mimo statusu *draft*, bo tak zaplanował go dyrektor epiku. Specyfikacja nadal czeka na przegląd właściciela. R6 wdrożono według decyzji właściciela: próba bez katalogu przestrzeni ma własny folder przebiegu, także przy ponowieniu; kroki przestrzeni pracują w jej katalogu, w jednym katalogu po kolei, w różnych równolegle. Przydział jest atomowy w obrębie jednego procesu schedulera, a wiele procesów pozostaje poza zakresem. Analiza B20 należy do kolejnego kroku.
- **Stan wdrożenia (2026-11-21, krok 4 epiku).** Status interfejsu z S3 i S6 jest wdrożony: „wolny” (0/N), „w toku” poniżej limitu (np. „2/6 in progress”) i „zajęty” dopiero przy limicie, na stronie zespołu, w pasku czatu, przy ikonach i w liście członków dla dyrektora (z liczbą wolnych miejsc i zasadą preferowania członków z wolnymi miejscami przy planowaniu). Interfejs jest po angielsku jak reszta aplikacji. Zastępuje to etykiety zajęty/wolny ze spec 023 i jej R8 w zakresie licznika.
- **Stan wdrożenia (2026-11-21, krok 5 epiku).** Testy odbiorcze S1–S5 z kontrolowanym executorem: sześć nakładających się zadań jednego agenta w sześciu przestrzeniach z osobnymi katalogami, siódme w kolejce, zwolnienie slotu po błędzie executora i po braku katalogu przestrzeni, osobny katalog ponowienia, 10 aktywnych przebiegów przy limicie 10 z równoległymi zapisami w obu bazach. Część S5 dotycząca ruchu HTTP przy 10 przebiegach i analiza B20 pozostają do wykonania.
