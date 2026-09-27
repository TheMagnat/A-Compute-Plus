# Acerola Compute Plus

> Acerola Compute Plus is a fork of Acerola Compute which aims to push this project to its full potential to make writing compute shaders for your games as simple as possible

Acerola Compute (ACompute for short) is a compute shader wrapper language for GLSL compute shaders intended for use with Godot to make compute shader organization, compilation, memory management, and dispatching much simpler.

## Using ACompute Shaders

Because ACompute is technically a custom shader language, it needs its own interpreter which is provided with the script `acerola_shader_compiler.gd`.

## Plus Features

> List the differences with the original Aeroal Compute

- Parsing include files using the `#include "path"` instruction in your ACompute Shaders.
- Ability to use Local Devices instead of Global Rendering Devices.
- Usage of storage buffers.
- Merges "#kernel" and "[numthreads(x, y, z)]" declarations with an unique "#kernel [numthreads(x, y, z)]" to put before your functions. Inspired from [Essojadojef](https://github.com/Essojadojef) work.
- New custom resource `AComputeShader`. This resource got it's own `EditorImportPlugin`, allowing Godot editor to scan and import our files. They are then pre-parsed and stored as ResourceFiles. The `AcerolaShaderCompiler` just have to compile the code directly. This allow us to make usage of the Godot auto-reimport system and signals for the hot reload (without having to scan every frames for any changes which was the old way). The resources are shown in the editor when the plugin is activated and clicking on it will open the ACompute shader file in an external editor. This was sugested by [nonchip](github.com/GarrettGunnell/Acerola-Compute/issues/6).
- Caching the SPIR-V code inside `AComputeShader`.

## Usage

You can refer to the demo project to see how to use the addon.

* You can set `interface/editor/behavior/import_resources_when_unfocused` in your editor settings to true if you want your shaders to be reloaded when Godot is not focused.

## Limitations

- ~~Having more than one ACompute shader with the same name does not work to the way we store shaders. This is a limitation that could be easily fixed.~~ Fixed with `AComputeShader`
- ~~Hot reloading does not work with new files. You must restart your scene.~~ Fixed with `AComputeShader`
- Using sparse binding in your ACompute shaders (ex: 0, 2, 3) will result in an error. This is a limitation that could be easily fixed.
- Currently editing an include file won't trigger a Hot Reload, I'm planning to add this features soon.

## Planned

* Make usage of "shader_compile_binary_from_spirv" to go further with the caching, allowing us to cache a compiled version of the kernels on local clients, but it have to be done at runtime since it's GPU and Driver dependant.
* Watch for include files changes for hot reloading to work with includes.

## Contributing

Feel free to request any features and open any pull request, I'll take the time to look at all that :)
