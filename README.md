# Miniature shader

This is a fork of [https://github.com/mateuskreuch/minecraft-miniature-shader](https://github.com/mateuskreuch/minecraft-miniature-shader).

It adds the missing part of the Voxy integration which got it to work in 26.3 (other versions untested).
This was done AI-assisted. I have no idea about Shader development, so i don't feel like i could contribute the isolated commit which added this to upstream. But feel free to take over and do it.

After getting Voxy to work, i realized that the fog settings of Miniature don't play nicely with it, as they do nothing if Voxy is enabled due to some hardcoded fog distance settings if Voxy is enabled. So i let it rework this too. The "Overworld Fog" slider now works linearly from 0 (no fog) to 10 (fog that seems to remove Voxy distance rendering) and is highly opinionated by me. Building Shaders and make these informed decisions is rather hard as i learned. Much Kudos to Matheus Kreuch for this Shader, since it is perfect for playing Matcha Flavoured with it :)

I don't plan to put this version up on any Mod site. Take it as is if you like. You can also just download it up to the voxy commit and leave the rest of my customizations alone.

![illustration](https://github.com/mateuskreuch/minecraft-miniature-shader/blob/main/README_IMG.png?raw=true)
