# Save and close the block editor — 1.0.10 (19)

- Mac and Windows show **Save and Close Block** above the canvas while editing a block. It applies changes to every instance of the block and returns to the previous drawing view or sheet.
- `BCLOSE Save` or `BC S` does the same from the command line and scripting API. `BCLOSE Discard` discards changes since the last block save. Undo reopens the edit session.
- Use Cmd+S on Mac or Ctrl+S on Windows to write the updated `.archi` file. The document format is unchanged.
