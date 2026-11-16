# PresentStage

Present a local slide deck with separate windows for the audience and speaker. The speaker window shows editable notes, slide timing and an elapsed timer. Slides, images and videos travel with the exported presentation.

## Build a presentation

Run these commands from this directory, with your deck and output paths pointing to your own project:

```sh
python3 build.py path/to/deck.json -o path/to/talk.html
./chrome path/to/talk.html
```

The first command creates a single offline HTML file with Python 3's standard library. The second opens two synchronized Google Chrome windows on macOS. You can also open the HTML in Chrome and press **P** to open the companion window. Presenter notes are included in this file.

To build a standalone macOS application, use `python3 build.py path/to/deck.json -o path/to/Talk.app`. This requires Swift and the macOS command-line developer tools. Open the app to launch both windows. When an external display is connected, the app places the audience window there.

## Deck format

The input is a UTF-8 JSON object. Its optional `title` names the presentation. Its required `slides` array defines the running order and must contain at least one visible slide. Each slide accepts the following fields:

| Field | Value |
| --- | --- |
| `title` | Plain text displayed on the slide and in the speaker window |
| `body` | An HTML fragment for the slide body. Use self-contained markup and trust the source as you would a local web page. |
| `media` | Path to an image or video, resolved relative to the JSON file and embedded at build time |
| `notes` | Plain text shown to the speaker |
| `time` | Optional timing label shown to the speaker |
| `hidden` | Boolean. Set to `true` to skip the slide. |

The builder also accepts the earlier offline presenter HTML format with a slide stage, a navigation bar and an embedded notes array. To present that file in Chrome with its original controls and saved notes, pass it directly to `./chrome`.

## Present

Press **Right**, **Space**, or right-click once to start the timer on the first slide. Advance again to change slides. **Left** goes back. Click the notes to edit them and press **Esc** to resume keyboard navigation. Edits are saved locally for that deck. HTML and native presentations use separate note stores.
