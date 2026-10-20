# Modellkatalog

Stand: 20.10.2026. Die Größen stammen aus den verlinkten Repository-Snapshots beziehungsweise den Ollama-Modellseiten. Für Servervarianten sind die Größen Näherungswerte; das Backend kann andere Dateien verwenden.

| Modell | Ausführung | Download ca. | RAM empfohlen | Lizenz |
| --- | --- | ---: | ---: | --- |
| [Qwen3 0,6B](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit) | MLX in der App | 0.35 GB | 4 GB | apache-2.0 |
| [Qwen3 1,7B](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit) | MLX in der App | 0.98 GB | 6 GB | apache-2.0 |
| [Qwen3 4B](https://huggingface.co/mlx-community/Qwen3-4B-4bit) | MLX in der App | 2.28 GB | 8 GB | apache-2.0 |
| [Qwen3 8B](https://huggingface.co/mlx-community/Qwen3-8B-4bit) | MLX in der App | 4.62 GB | 16 GB | apache-2.0 |
| [Qwen3 14B](https://huggingface.co/mlx-community/Qwen3-14B-4bit) | MLX in der App | 8.32 GB | 24 GB | apache-2.0 |
| [Qwen3 30B-A3B](https://huggingface.co/mlx-community/Qwen3-30B-A3B-4bit) | MLX in der App | 17.19 GB | 32 GB | apache-2.0 |
| [Qwen2.5 1,5B Instruct](https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit) | MLX in der App | 0.88 GB | 6 GB | apache-2.0 |
| [Qwen2.5 3B Instruct](https://huggingface.co/mlx-community/Qwen2.5-3B-Instruct-4bit) | MLX in der App | 1.75 GB | 8 GB | qwen-research |
| [Qwen2.5 7B Instruct](https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit) | MLX in der App | 4.30 GB | 12 GB | apache-2.0 |
| [LFM2.5 1,2B Instruct](https://huggingface.co/mlx-community/LFM2.5-1.2B-Instruct-4bit) | MLX in der App | 0.66 GB | 6 GB | lfm1.0 |
| [LFM2.5 1,2B Thinking](https://huggingface.co/mlx-community/LFM2.5-1.2B-Thinking-4bit) | MLX in der App | 0.66 GB | 6 GB | lfm1.0 |
| [LFM2.5 8B-A1B](https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-MLX-4bit) | MLX in der App | 4.85 GB | 12 GB | lfm1.0 |
| [LFM2.5 24B-A2B](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-MLX-4bit) | MLX in der App | 13.59 GB | 24 GB | lfm1.0 |
| [Llama 3.2 1B Instruct](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit) | MLX in der App | 0.71 GB | 6 GB | llama3.2 |
| [Llama 3.2 3B Instruct](https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit) | MLX in der App | 1.82 GB | 8 GB | llama3.2 |
| [Gemma 3 1B](https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit) | MLX in der App | 0.77 GB | 6 GB | gemma |
| [SmolLM3 3B](https://huggingface.co/mlx-community/SmolLM3-3B-4bit) | MLX in der App | 1.75 GB | 8 GB | apache-2.0 |
| [Nemotron 3.5 Lightning · Nota](https://huggingface.co/nota-ai/Nemotron-3.5-Lightning-30B-A3B-Nota-Ternary-MLX-1014) | Hier nicht unterstützt | 10.25 GB | 24 GB | openmdw-1.1 |
| [Ornith 1.5 9B](https://ollama.com/library/ornith-1.5) | Separater lokaler Server | 6.60 GB | 16 GB | Siehe Anbieterbedingungen |
| [Ornith 1.5 35B-A3B](https://ollama.com/library/ornith-1.5) | Separater lokaler Server | 23.00 GB | 32 GB | Siehe Anbieterbedingungen |
| [LFM2.5 8B-A1B · Ollama](https://ollama.com/library/lfm2.5) | Separater lokaler Server | 5.20 GB | 12 GB | Siehe Anbieterbedingungen |
| [LFM2.5 24B-A2B · Ollama](https://ollama.com/library/lfm2.5) | Separater lokaler Server | 15.00 GB | 24 GB | Siehe Anbieterbedingungen |
| [LFM2.5 Thinking 1,2B · Ollama](https://ollama.com/library/lfm2.5-thinking) | Separater lokaler Server | 0.73 GB | 6 GB | Siehe Anbieterbedingungen |
| [Nemotron 3 Nano 4B](https://ollama.com/library/nemotron-3-nano) | Separater lokaler Server | 2.90 GB | 8 GB | Siehe Anbieterbedingungen |
| [Nemotron 3 Nano 30B](https://ollama.com/library/nemotron-3-nano) | Separater lokaler Server | 24.00 GB | 32 GB | Siehe Anbieterbedingungen |
| [MiniCPM-V 4.7 35B-A3B](https://ollama.com/library/openbmb/minicpm-v4.7) | Separater lokaler Server | 22.00 GB | 32 GB | Siehe Anbieterbedingungen |

## Die vorgeschlagenen Modelle

- **LFM2.5 1,2B Instruct:** auf diesem M2 direkt mit MLX geladen und mit echter Textgenerierung geprüft. Vollständiger Snapshot: 663.394.269 Bytes, neun geprüfte Dateien, Revision `dee2f8a2786e6648bb644a7ca40652842490034b`.
- **LFM2.5 Thinking 1,2B:** Architektur vorhanden, noch nicht praktisch geprüft. Der Denkmodus kann das derzeitige Ausgabelimit erreichen.
- **LFM2.5 8B-A1B:** 4,85 GB MLX-Snapshot; Architektur `lfm2_moe` in MLX Swift vorhanden. Auf 16 GB größenmäßig plausibel, noch nicht praktisch geprüft.
- **LFM2.5 24B-A2B:** 13,59 GB MLX-Snapshot. Für diesen Mac mit 16 GB einschließlich macOS und Laufzeit nicht empfohlen. Mindestens 24 GB als Planungsempfehlung, keine Betriebsgarantie.
- **Nota Nemotron 3.5 Lightning:** Snapshot mit 10,25 GB einschließlich Tokenizer/Metadaten. Ternäre Werte in einem nativen 2-Bit-Affine-Container; kein eigener Kernel erforderlich laut Anbieter. Trotzdem passt die Architekturkonfiguration nicht zu MLX Swift 3.32.3: `layers_block_type` statt des erwarteten `hybrid_override_pattern`. Deshalb kein Download-/Startknopf in dieser App.
- **Ornith 1.5:** lokale Ollama-Tags 9B und 35B aufgenommen. Die 9B-Ausgabe ist auf 16 GB als knapp eingeordnet, 35B benötigt mehr Speicher. Bilder werden vom Arbeitsbereich derzeit nicht an das Modell übergeben.
- **Nemotron 3 Nano:** lokale Ollama-Tags 4B und 30B im Katalog. Cloud-Tags werden weder angeboten noch zur Generierung akzeptiert.

## Empfehlung und Grenzen

Die App liest Chip, RAM, CPU-Kerne und freien Speicher lokal aus. Die Einstufung berücksichtigt Apple Silicon, unterstützte Laufzeit, Gewichtsgröße, eine geschätzte Laufzeitreserve und 4 GB für macOS. Die Schätzung bezieht sich auf den auf 8K begrenzten KV-Cache dieser App. Bei MoE zählt weiterhin der gesamte Gewichtsbestand, nicht nur die aktive Parameterzahl.

Die Sortierung kombiniert diese Grenzen mit einer Modellgröße relativ zum RAM und einer kuratierten Priorität für Textaufgaben. Praktisch geprüfte Modelle erhalten einen kleinen Vorrang. CPU-Kerne werden angezeigt; es wird daraus keine Geschwindigkeit berechnet. Es gibt keinen behaupteten Qualitäts- oder medizinischen Eignungswert. Speicherwerte sind Planungswerte, keine gemessenen Spitzenverbräuche.

Die vollständigen versionierten Metadaten liegen in `Sources/LocalKIWorkspace/Resources/ModelCatalog.json`. Neue native Modelle erfordern eine Architekturprüfung und feste Revisionen. Der Katalog lädt sich beim Öffnen nicht aus dem Internet.

## Referenzen

- [MLX Swift: LLM-Registrierung 3.32.3](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Libraries/MLXLLM/LLMModelFactory.swift)
- [LFM2.5 24B Modellkarte](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B-MLX-4bit)
- [Nota Modellkarte und Format](https://huggingface.co/nota-ai/Nemotron-3.5-Lightning-30B-A3B-Nota-Ternary-MLX-1014)
