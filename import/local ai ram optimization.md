# Running a 35B AI Model on 6GB VRAM, FAST (llama.cpp Guide)

This file is a transcript and summary of this video: https://www.youtube.com/watch?v=8F_5pdcD3HY

## Transcript

00:00:00
Can you run a 35-billion-parameter AI on an 8-year-old GPU with only 6 gigs of VRAM at acceptable speed? Yes, you can. We are going to explore every way to not just run this model, but run it fast enough that it doesn't feel like you're talking through a satellite phone. And we're going to run it on the full context and making it usable, not just possible. Five tricks, one Docker command, let's get into it. Before we touch any flags, let me introduce the three characters in this story. First,

00:00:33
llama.cpp, the engine. I'm using llama.cpp because it gives you crazy flexibility. Every knob exposed, every memory decision yours to make. If you want to micromanage where each piece of the model lives, and we will, this is the tool. Second character, Qwen 3.6 35B A3B, the model. Total size, 35 billion parameters, but it's a mixture of experts, so only 3 billion are active for any given word. 256 tiny specialists. Eight of them wake up per token. Hold that thought, we'll come back to it. Third character, the

00:01:13
worst-case rig I had on hand, built almost 8 years ago. Specifically, 8-year-old GTX 1060 with 6 gigs of VRAM on PCIe Gen 3. 8-year-old i3 8100, four cores, no hyperthreading. 24 gigs of DDR4. Nothing on this list would impress anyone in 2026. If your setup is better than this, and it almost certainly is, your numbers will come out better than mine. The point is that this rig is a floor, not a ceiling. Cast introduced. Let's start with a dumb thing first, the way most people would actually try it,

00:01:51
the obvious move. Split the model in half. Top half on the GPU, bottom half on the CPU and RAM. Do as much as fits, push the rest off board. That's what dash NGL does. Number of GPU layers. We tell it 20, meaning the first 20 layers go on the card, the rest stay on the CPU. It loads, just barely, and the model starts answering at about three tokens a second, which means watching a sentence appear over 20-30 seconds. We're in satellite phone territory. Why is it crawling? Because every layer

00:02:26
carries its experts with it. When a layer is on the CPU, the entire layer, including its expert blocks, lives on the CPU. And per token, the data has to make the trip across PCIe. The bus chokes. Three tokens a second, useless for anything real time. So, this is our floor, the dumb baseline. Now, the question becomes, what do we know about this model that the dumb baseline doesn't? And this is where the type of model we are running starts to matter. Most older AI models are what they called dense.

00:03:01
Every neuron in every layer fires for every word. If a dense model has 35 billion parameters, all 35 billion run. Mixture of experts is different. The bulk of the weights live in those expert blocks. Per token, the model only wakes up a handful of them, which means most of the model is sleeping most of the time. Dead weight if you're sitting on the GPU, but cheap rent if you're sitting in RAM. So, the smart split isn't half the layers each. It's keep the small, fast-firing parts on the GPU,

00:03:41
push the giant sleeping experts onto the CPU. Per token, the GPU does its job, then asks for whichever eight experts are needed, then does its job again. llama.cpp has the exact flag for this. --n-cpu-moe 41. Take every layer's experts and pin them to the CPU. Everything else, send to the GPU. Reload. Same model, same hardware, one different flag. Speed jumps from three tokens a second to 10. 230% faster, no hardware change. That'd be the end of most YouTube videos. Cool trick, runs at reading speed, ship

00:04:28
it. But there's four more flags. Each one makes it faster. All right, on to the next one. Flag two, no mmap. By default, llama.cpp does this clever thing. It pretends the whole model file is in RAM, but really, it's still on the disk. The OS pages chunks in only when they're needed. Sounds smart, it's actually slow for what we are doing. Every few tokens, the model asks for an expert that hasn't been loaded yet. Disk read, wait, token comes out late. With no mmap, llama.cpp reads the entire model into RAM upfront,

00:05:06
the whole 20 gigs. Once it's there, every expert is already loaded. No more disk reads during inference, no more page faults mid-token. Every lookup is predictable. 10 tokens a second jumps to 13 and a half, about a 35% bump from one flag. No code, no retraining, no quantization tricks, just telling the OS, "Hey, stop being clever about my RAM." Two flags down, three to go. Now, check the GPU. At 13 tokens a second, it still isn't full. Two whole gigabytes of VRAM just sitting there, free real

00:05:39
estate we can spend. So, we change one number from 41 down to 35. That pulls six layers worth of experts from the CPU back onto the GPU. More work happens on the fast chip, less crosses the PCIe bus. VRAM goes from 4 gigs to 5 and a half. Speed jumps from 13 and a half to 17. There's a trade-off, by the way. The bigger the GPU's footprint, the less room for the context window. We dropped from 100,000 tokens of context down to about 64,000. Fine for most chats, not fine if you're feeding it a whole code

00:06:14
base. Hold that thought. 17 tokens a second, faster than I read out loud on a card from when Bohemian Rhapsody was in theaters. Three flags, 17 tokens a second. We could honestly stop here, but I want my context back. Real quick, if you like seeing what old hardware can actually do, I do this every couple weeks. New model, cheap setup, no cloud bill. Subscribe and you'll catch the next one. Right, back to it. Remember that context window we had to shrink? Time to get it back. We're at 17 tokens a second, but context

00:06:47
is chopped down to 64,000 tokens. To get more, you'd usually need more VRAM, which we don't have. Here's why context costs VRAM. Every token you've ever shown the model, the model remembers. Specifically, it stores two numbers per token per layer, keys and values, the KV cache, and it grows linearly. Twice the context, twice the memory. Heads-up, I was already using Q8 quantization on the cache. Q8 is basically lossless, negligible quality drop. But push past Q8, Q4, Q3, and the answers start to

00:07:24
fall apart. Earlier this year, Google DeepMind published Turbo Quant, random rotation then aggressive quantization. Four bits for keys, three for values, and somehow still almost lossless. Q3 and Q4 territory with quality you can't tell apart from Q8. The math is in the paper if you're into that. Two flags, turbo four for the keys, turbo three for the values. The asymmetry isn't a typo. This model uses grouped query attention with an 8:1 ratio, so the keys can take heavier compression than the values.

00:07:57
Don't worry about it, just type the flags. Okay, flags on. First, let's not get greedy. Bump context from 64,000 back to 128,000. Reload. It loads. 5.3 gigs of VRAM, 128K context, no OOM. That's already a win. Half a flag and we double the context, but only 0.7 gigs free. Can we be greedier? Push it to 256,000. Reload. Out of memory. Wait, what if we pull one more layer of experts back to the CPU? NCPU-MOE goes from 35 to 36. Try again. It fits, just barely. 5.9 of 6 gigs. 64,000 stretches to 256,000,

00:08:45
four times the entire training context of the model, on the same 6-gig GPU. Speed, still 17 tokens a second, same as before. Compression doesn't slow it down. The cache is small enough that the lookup is essentially free. What that gets you in practical terms? You can paste a small book in and ask questions about it. You can drop an entire code base as context without the model forgetting page one by the time it reads page 50. Four flags, same speed, four times the context. That's the Turbo

00:09:18
Quant trick. One paper, two flags, free real estate. One more flag and we're done. This one isn't about speed. It's the difference between a setup that works in a demo and a setup that survives Tuesday. There's a problem you don't see until you leave the server running for a day. Check this. Mlocked, 12 kilobytes. 12, as in basically nothing. All those experts we put in RAM, the kernel thinks they're regular files. Hours later, when memory gets tight or the system idles, it

00:09:51
starts paging some of them out to disk. Next inference, page fault, stutter, random slow tokens. The fix is annoying because it lives in three places. The LXC container needs permission to lock memory. Docker needs the IPC lock capability. llama.cpp needs the mlock flag. Skip any one of them and it silently falls back to default. No error, just a slow leak. With all three in place, you literally tell the kernel, do not touch this RAM. Do not page it. Do not move it. It's mine. Recheck meminfo. mlocked 16 GB. Every

00:10:31
expert is glued in place. The day three slowdown? Gone. Same 17 tokens a second, by the way. The speed didn't change because in a fresh boot, the experts were already cached. What changed is that this thing now runs for a week without degrading. Production behavior. Five flags. That's the whole list. 35 billion parameters, 6 gigs of VRAM, 256,000 tokens of context, 17 tokens a second. Stable. Okay, so we're done with the wins. Five flags, one Docker command, 17 tokens a second. Now I want to talk

00:11:10
about the thing I tried that didn't work because most videos skip that part. Speculative decoding. The idea is beautiful. You run a tiny model alongside the big one. The tiny one guesses the next eight tokens. The big one verify them in a single batch instead of eight serial passes. When it works, you get two to four times the speed. I added Qwen 3.5, the 800 million parameter version, as the drafter. Same tokenizer as the target. 248,000 tokens. Should plug right in. The drafter held its own. Acceptance came in around 65%.

00:11:48
Two out of every three guesses landed. Solid for an 800 million parameter draft. And the speed dropped from 17 to 11. Slower, even with decent predictions. That broke my brain for a day. Here's why it doesn't work. Two reasons. Both architectural. First, mixture of experts. Each token in the batch picks its own eight experts out of 256. Eight tokens batched together can pull from 64 different experts per layer. Each one fetched fresh from CPU RAM over the PCIe bus. The verification stops being a batch and turns into a

00:12:26
memory thrash. Second, this model uses state space layers. 30 out of 40 layers are SSM. SSM layers compute one position at a time. Each step depends on the state of the step before it. You can't parallelize them across a draft window. So the verify eight tokens in one pass trick doesn't apply. The math actually goes the wrong way. Per token verification time stays the same when you batch because expert loading dominates. Plus, you paid the cost of running the draft model. Net negative. Someone benchmarked this on a 3090

00:13:05
across 19 different configurations. Same result. Speculative decoding works for transformers. It doesn't work for what we are running. There's a follow-up paper called Dflash, block diffusion drafter. Generates eight tokens in one shot instead of one at a time. There's a working drafter for Qwen 3.6's 27 billion dense version. Different model, same trick I want, finally working. Worth coming back to. All right, let's wrap. Here's the whole thing. One Docker command, five flags that

00:13:38
matter. 35 billion parameters, 6 gigs of VRAM, 256,000 tokens of context, 17 tokens a second on a card older than every AI startup you've heard of. The hardware isn't the bottleneck anymore. The defaults are. And remember, these numbers came off about the worst case rig you can dig up in 2026. Eight-year-old GPU, eight-year-old CPU, plain DDR4. If you've got anything from this decade, newer card, faster RAM, PCIe Gen4, your numbers will go up. This is the floor. What you can actually run

00:14:19
on the card already in your machine is bigger than what the AI press tells you. Most of the work is done. You just have to know which flags to set. There's a follow-up worth trying. Dense 27 billion model, the Dflash drafter. See if we can crack 25 tokens a second on the same 1060. If it works, that's a different kind of crazy. If it doesn't, you'll get the same honest write-up. Honest question for the comments. What's a real workload you'd want to run on this setup? Codebase Q&A, long doc

00:14:55
summarization, some weird local agent thing. Drop it below. I'm curious what people would actually use this for. That's it. See you in a couple of weeks.


## Summary

### Zusammenfassung

Dieses Video demonstriert, wie ein großes KI-Modell mit **35 Milliarden Parametern** auf einem veralteten Computer mit einer **8 Jahre alten GPU (GTX 1060, 6 GB VRAM)** und einem schwachen CPU (Intel i3-8100, 4 Kerne, kein Hyperthreading) effizient ausgeführt werden kann. Trotz der limitierten Hardware wird eine akzeptable Geschwindigkeit von **17 Tokens pro Sekunde** erreicht, was schneller als das Lesen des Sprechers ist. Dies gelingt durch eine Kombination von **fünf optimierenden Flags** und einem einzelnen Docker-Befehl unter Verwendung des Frameworks **llama.cpp**.

### Wichtige Charaktere im Setup

| Charakter         | Beschreibung                                                                                  |
|-------------------|----------------------------------------------------------------------------------------------|
| **llama.cpp**     | Flexibles Open-Source-Toolkit, das viele Speicher- und Ausführungsoptionen bietet.           |
| **Qwen 3.6 35B**  | KI-Modell mit 35 Milliarden Parametern, bestehend aus einem „Mixture of Experts“-Modell, bei dem pro Token nur 3 Milliarden Parameter aktiv sind (8 von 256 Experten pro Token). |
| **Alte Hardware** | GTX 1060 mit 6 GB VRAM, Intel i3-8100 CPU, 24 GB DDR4 RAM, PCIe Gen3 – ein Worst-Case-Szenario für 2026. |

### Chronologischer Ablauf der Optimierungen

| Schritt                             | Maßnahme                                                                                   | Ergebnis                                                                          |
|-----------------------------------|-------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| **Baseline**                      | Modell halbiert: obere Hälfte GPU, untere Hälfte CPU (20 Layer GPU, Rest CPU)              | 3 Tokens/Sekunde, starke Verzögerung durch PCIe-Übertragungen, kaum nutzbar.     |
| **Flag 1: Experten auf CPU**      | Alle Experten (Großteil der Parameter) auf CPU, Rest auf GPU (--n-cpu-moe 41)              | 10 Tokens/Sekunde (+230% Geschwindigkeit), ohne Hardwareänderung.                |
| **Flag 2: Kein mmap**             | Modell komplett in RAM laden, statt auf Paging zu vertrauen                                | 13,5 Tokens/Sekunde (+35%), keine Verzögerungen durch Festplattenzugriff.        |
| **Flag 3: Experten teilweise zurück auf GPU** | Experten von 41 auf 35 Layer auf CPU, 6 Layer auf GPU                                        | 17 Tokens/Sekunde, VRAM-Auslastung 5,5 GB, Kontextfenster sinkt von 100k auf 64k Tokens. |
| **Flag 4: Turbo-Quantisierung des KV-Caches** | Quantisierung der Keys mit 4 Bits, Values mit 3 Bits (Turbo Quant), Kontextfenster verdoppeln auf 128k, später 256k Tokens | Kontext 256.000 Tokens, gleiche Geschwindigkeit (17 Tokens/Sekunde), VRAM knapp 6 GB. |
| **Flag 5: Memory Lock (mlock)**   | Experten im RAM vor Paging schützen, Docker und Container entsprechend konfigurieren       | Kein Leistungsverlust über lange Laufzeiten, stabile Performance ohne Einbrüche.  |

### Kerntechnische Erkenntnisse

- **Mixture of Experts (MoE):** Nur ein kleiner Teil der Experten wird pro Token aktiviert, was Speicher- und Rechenressourcen optimiert, aber die Verteilung auf CPU/GPU erfordert sorgfältige Planung.
- **PCIe-Bandbreite als Flaschenhals:** Häufige Datenübertragungen der Experten zwischen CPU und GPU bremsen das System stark.
- **Quantisierung:** Turbo Quant ermöglicht eine signifikante Kontextvergrößerung ohne Qualitätsverlust, indem Keys und Values unterschiedlich stark komprimiert werden.
- **Memory Lock:** Verhindert, dass der Kernel Speicherbereiche auslagert, was langfristige Störungen durch Paging vermeidet.
- **Hardware-Floor:** Selbst mit sehr alter Hardware sind akzeptable Leistungswerte erreichbar; neuere Hardware verbessert die Performance weiter.

### Fehlgeschlagene Methode: Spekulatives Decoding

- Idee: Ein kleineres Modell (Qwen 3.5 mit 800 Mio. Parametern) soll als „Drafter“ fungieren und Token vorschlagen, die das große Modell dann batchweise validiert, um Geschwindigkeit zu erhöhen.
- Ergebnis: Geschwindigkeit sinkt von 17 auf 11 Tokens/Sekunde.
- Gründe:
  - MoE-Modell aktiviert pro Token unterschiedliche Experten, was im Batch zu speicherintensivem „Thrashing“ führt.
  - Verwendung von State Space Layers (SSM) bei 30 von 40 Layern, die sequenziell berechnet werden müssen und nicht parallel batchfähig sind.
- Fazit: Spekulatives Decoding funktioniert bei Transformer-Modellen, aber nicht bei Qwen 3.6 mit Mixture of Experts und SSM-Architektur.

### Zusammenfassung der Leistungsdaten

| Parameter                      | Wert                              |
|-------------------------------|----------------------------------|
| Modellgröße                   | 35 Milliarden Parameter          |
| Aktive Parameter pro Token    | 3 Milliarden (8 Experten von 256)|
| GPU-Hardware                 | GTX 1060, 6 GB VRAM              |
| CPU-Hardware                 | Intel i3-8100 (4 Kerne)          |
| Kontextfenster (Tokens)      | Bis zu 256.000 Tokens            |
| Geschwindigkeit             | 17 Tokens/Sekunde                |
| Speicher (VRAM) Nutzung      | Ca. 6 GB                         |

### Fazit und Ausblick

- **Erfolgreiche Ausführung eines großen MoE-KI-Modells auf sehr alter Hardware** ist möglich, wenn man die richtigen Software-Flags und Speicherstrategien nutzt.
- Die **Hauptlimitierung liegt in den Software-Defaults und Speicherverwaltung**, nicht in der Hardware selbst.
- Das Video zeigt den „Boden“ der Performance, mit der der Nutzer arbeiten kann; bessere Hardware bringt automatisch bessere Ergebnisse.
- Ein Folgeexperiment mit einem **dichtem 27-Milliarden-Parameter-Modell** und dem „Dflash Drafter“ wird angestrebt, um höhere Geschwindigkeiten (>25 Tokens/Sekunde) zu erreichen.
- Der Sprecher lädt ein, reale Anwendungsfälle für dieses Setup (z.B. Codebase Q&A, lange Dokumentzusammenfassung) in die Kommentare zu schreiben.

### Schlüsselbegriffe

- **Mixture of Experts (MoE)**
- **Quantisierung (Turbo Quant)**
- **Memory Lock (mlock)**
- **Spekulatives Decoding**
- **State Space Layers (SSM)**
- **llama.cpp**
- **GPU/CPU Speicherverteilung**
- **Kontextfenster**

---

Diese Analyse zeigt, dass durch geschickte Software-Optimierungen auch auf sehr begrenzter Hardware komplexe KI-Modelle mit großer Kontextlänge und akzeptabler Geschwindigkeit nutzbar gemacht werden können.