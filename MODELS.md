# Modelle in Aurora

Stand: 02.11.2026. Die Bibliothek zeigt zehn kuratierte MLX-Modelle für lokale Textaufgaben. Die Auswahl berücksichtigt Modellgröße, verfügbare Architektur in der eingebundenen MLX-Swift-Version und unterschiedliche Hardware; sie ist keine unabhängige Qualitätsrangliste. Bereits installierte ältere Katalogmodelle bleiben unter „Installiert“ verfügbar.

| Modell | Download ca. | RAM empfohlen | Status |
| --- | ---: | ---: | --- |
| [Qwen3.5 0,8B](https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit) | 0,65 GB | 8 GB | noch nicht praktisch geprüft |
| [Qwen3.5 2B](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit) | 1,75 GB | 8 GB | noch nicht praktisch geprüft |
| [Qwen3.5 4B](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit) | 3,06 GB | 12 GB | noch nicht praktisch geprüft |
| [Qwen3.5 9B](https://huggingface.co/mlx-community/Qwen3.5-9B-4bit) | 5,98 GB | 16 GB | noch nicht praktisch geprüft |
| [Qwen3 4B Instruct 2507](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) | 2,28 GB | 8 GB | noch nicht praktisch geprüft |
| [Gemma 4 E2B](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit) | 3,58 GB | 12 GB | noch nicht praktisch geprüft |
| [Gemma 4 E4B](https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit) | 5,18 GB | 16 GB | noch nicht praktisch geprüft |
| [LFM2.5 1,2B Instruct](https://huggingface.co/mlx-community/LFM2.5-1.2B-Instruct-4bit) | 0,66 GB | 6 GB | lokale Textgenerierung geprüft |
| [LFM2.5 8B-A1B](https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-MLX-4bit) | 4,85 GB | 12 GB | noch nicht praktisch geprüft |
| [Qwen3 0,6B](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit) | 0,35 GB | 4 GB | lokale Textgenerierung geprüft |

Die Downloadgrößen basieren auf festgelegten Modellständen und sind Näherungswerte. RAM-Angaben berücksichtigen Gewichte, geschätzte Laufzeitreserve und macOS; sie sind keine Messung des Spitzenverbrauchs. Qwen3.5 und Gemma 4 sind multimodale Modellfamilien, Aurora übergibt derzeit ausschließlich Text. Für die sieben neu aufgenommenen Snapshots sind Konfiguration und Architekturzuordnung geprüft, ihre tatsächliche Inferenz in Aurora muss noch einzeln getestet werden. Modelllizenzen sind über die Modellquellen einsehbar.

Modellgewichte sind nicht im Repository enthalten. Die Bibliothek lädt öffentliche Gewichte nur nach ausdrücklicher Freigabe des Offline-Modus herunter. Der Modellkatalog wird nicht automatisch aktualisiert. Die App begrenzt Eingaben auf 6.000 und Ausgaben auf 1.536 Tokens; Denkmodus kann das Ausgabelimit früh erreichen.
