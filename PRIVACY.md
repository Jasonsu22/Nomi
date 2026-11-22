# Privacy policy

Nomi is built to keep your lectures on your own computer. This policy covers the Mac and Windows apps and the website [nomi.software](https://nomi.software).

## What stays on your computer

- **Your lectures stay with you.** Recordings, transcripts, translations, summaries, your questions and answers, the files you add, and Nomi's memory of your preferences are all stored only on your computer.
- **Transcription and translation run locally.** Speech recognition and translation run on your computer, and so do answers when you use a local model. Nothing you record is sent anywhere for that.
- **Your keys stay local too.** API keys and web-search keys are kept on your computer: in a file only your account can read on the Mac, and in Windows Credential Manager on Windows.

Nomi has no accounts, no analytics, no tracking and no advertising. We, the developers, receive nothing from the app.

## When Nomi connects to the internet

Nomi only goes online in these cases. Each one sends only what it needs to work:

| What | When | What is sent, and to whom |
| --- | --- | --- |
| Downloading models | When you download a model in the setup guide or Settings | Requests for the model files to Hugging Face (or its mirror, hf-mirror.com) |
| Checking for updates | About once a day | A request for the latest release information to GitHub |
| API models | Only if you add an API and choose it | Your question, and the lecture text and files you chose to include, to the provider you configured (for example OpenAI, Anthropic, DeepSeek or a local Ollama server) |
| Web search | Only if you set up a search service and turn on web search | Your search query, to the service you chose (Tavily, Exa or your own SearXNG) |
| Link previews | When you point at a web citation, if previews are on (Settings › Web search) | Requests for that website's icon and picture, to that website and to DuckDuckGo's icon service. Turn previews off to stop this |
| Contacting us | Only if you choose *Help › Contact us* | Nothing is sent by Nomi: it opens your own email app |

When you use an API model or web search, that provider's own privacy policy applies to what you send them.

## The website

nomi.software is a static page. It uses no cookies, no analytics and no tracking. It remembers the language you pick (English or 中文) in your own browser, and nowhere else. The download buttons link to GitHub, whose privacy policy applies to downloads.

## Deleting your data

Everything Nomi stores is in one place on your computer, so deleting it removes it completely:

- **Mac:** `~/Library/Application Support/Nomi`, plus local models in `~/.OminiX/models`.
- **Windows:** `%LOCALAPPDATA%\software.nomi.windows`. The uninstaller can remove this folder for you.

## Changes and contact

If this policy changes, the new version will be published here, in the project's repository. For questions, open an [issue](https://github.com/Jasonsu22/Nomi/issues) or use *Help › Contact us* in the app.
