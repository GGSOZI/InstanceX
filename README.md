# Instance X

Dex++ based explorer and properties for Roblox executors, with a copy suite built in: copy tools, GUIs and models, save instances, and record animations.

Revived/Upgraded by DuaKNo | Dex ++ by Chillz | Dex by Moons

## Run it

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/GGSOZI/InstanceX/main/loader.lua"))()
```

Only Explorer and Properties open on execute. Everything else is in the side menu.

## What is inside

- **Explorer + Properties** with search, drag, right click actions and the usual Dex++ tools
- **Copy** copies any GUI or tool as code you can run in other games
- **Tool Copy** lists your tools and copies them with models, meshes, textures and scripts
- **Recorder** logs animations, VFX and sound
- **Save Instance** saves the place or any object as `.rbxlx` / `.rbxmx`
- **Notepad, Console, 3D Viewer**

## Files

| File | What it does |
| --- | --- |
| `loader.lua` | tiny loader, downloads `Instance_X.lua` from this repo and runs it |
| `Instance_X.lua` | the full script |
| `modules/SaveInstance.lua` | standalone saver. Instance X loads it from here, and you can use it in your own scripts |

## Saving

Instance X uses the first one that works: your executor's own `saveinstance`, then `modules/SaveInstance.lua` from this repo, then the saver built into the script. Files go to your executor's `workspace` folder.

## Using the saver on its own

```lua
local save = loadstring(game:HttpGet("https://raw.githubusercontent.com/GGSOZI/InstanceX/main/modules/SaveInstance.lua"))()
save({ Object = game, FilePath = "MyPlace", Decompile = true })
save({ Object = workspace.Model, FilePath = "MyModel" })
```

## Notes

- Client side only. Anything the server owns will not be copied.
- Made for executors like Delta, Solara and Wave. Some executors lock functions such as `decompile`.
- If you fork the repo, change `USER`, `REPO` and `BRANCH` at the top of `loader.lua`.

## Credits

- Revived/Upgraded by **DuaKNo**
- Dex++ by **Chillz**
- Dex by **Moons**
- Toon (IY Dex and PRs), Cazan (3D Preview)

Instagram: [me_duakno](https://instagram.com/me_duakno)
Discord: https://discord.gg/empgqd5qpq
