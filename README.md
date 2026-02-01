# YARLIG

Yet Another Rogue-Like in Godot. Game Jam Edition.

## What is it?

This game is based on the original 1980s Rogue. "Based" is used loosely. "Game" is used loosely. The visual design was also inspired by Dwarf Fortress and Cataclysm.

This game was built as part of Hyper Game Dev's 7th Game-like Jam focusing on Rogue-like games. The jam was 31 days, though I used considerably less. Possibly like 10 or 11 days spread out over the 31.

If the project is continued after the Game Jam, there will be a separate page to track it.

## How do I play?

You are @. Use arrow keys to move. Walk into ! mobs to attack. Go deeper by stepping into the down stairs v. Backspace to start a new game.

## What is interesting about it?

Not much about gameplay itself is interesting. There might be more interesting under the hood though. The game barely uses Godot resources.

Besides a black background ColorRect, all elements in Godot are RichTextLabels. Animations are performed using a sort of double buffer of 2 RichTextLabels whose visibility are cycled between. The Renderer ensures the RichTextLabels always contain 25x80 (rows x columns) for display.

The world is tracked in a custom list of lists built as an Array2D class, which has an additional wrapper of a CenteredArray2D class so we can use x/y coordinates instead of rows and columns.
