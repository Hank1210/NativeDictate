# Third-Party Notices

NativeDictate 4.2 uses the following separately licensed components. NativeDictate itself remains available under the MIT License.

## FluidAudio

- Project: FluidAudio
- Version: 0.15.5, revision `19600a485baa4998812e4654b70d2bab8f2c9949`
- Source: <https://github.com/FluidInference/FluidAudio>
- Copyright: FluidInference contributors
- License: Apache License 2.0
- License copy: [THIRD_PARTY_LICENSES/FluidAudio-Apache-2.0.txt](THIRD_PARTY_LICENSES/FluidAudio-Apache-2.0.txt)

FluidAudio is compiled into the NativeDictate application. NativeDictate does not modify FluidAudio's source code.

## Parakeet TDT 0.6B v3 Core ML model

- Model: `FluidInference/parakeet-tdt-0.6b-v3-coreml`
- Version used by NativeDictate: v3 model layout supported by FluidAudio 0.15.5
- Download source: <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml>
- Upstream model: NVIDIA Parakeet TDT 0.6B v3
- License identifier published by the model repository: CC-BY-4.0

The model is not included in NativeDictate's source repository or Community ZIP. It is downloaded only after the user requests local transcription. Users should review the current model card and license at the download source before installing it. NativeDictate displays the model name, source, approximate size and license identifier before download.

## Apple frameworks

NativeDictate also uses system frameworks supplied with macOS, including AppKit, SwiftUI, AVFoundation, ScreenCaptureKit, Speech, Accessibility and Security. Their use is governed by Apple's applicable software license terms.
