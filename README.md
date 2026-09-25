# Acerola Compute Plus

> Acerola Compute Plus is a fork of Acerola Compute which aims to push this project to its full potential to make writing compute shaders for your games as simple as possible

Acerola Compute (ACompute for short) is a compute shader wrapper language for GLSL compute shaders intended for use with Godot to make compute shader organization, compilation, memory management, and dispatching much simpler.

## Using ACompute Shaders

Because ACompute is technically a custom shader language, it needs its own interpreter which is provided with the script `acerola_shader_compiler.gd`. This must be declared as a global singleton in your Godot project so that on start it will identify any `.acompute` files in your project and compile them automatically. For information on how to do this, please reference [this](https://docs.godotengine.org/en/latest/tutorials/scripting/singletons_autoload.html) tutorial in the Godot documentation.

## Plus Features

- Parsing include files using the `#include "path"` instruction in your ACompute Shaders
- Ability to use Local Devices instead of Global Rendering Devices
- Usage of storage buffers

## Usage

You can refer to the demo project to see how to use the addon.

## Limitations

- Having more than one ACompute shader with the same name does not work to the way we store shaders. This is a limitation that could be easily fixed.
- Hot reloading does not work with new files. You must restart your scene.
- Using sparse binding in your ACompute shaders (ex: 0, 2, 3) will result in an error. This is a limitation that could be easily fixed.

## Contributing

Feel free to request any features and open any pull request, I'll take the time to look at all that :)
