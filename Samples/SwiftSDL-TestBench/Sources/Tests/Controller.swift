import SwiftSDL

extension SDL.Test {
  final class Controller: Game {
    private enum CodingKeys: String, CodingKey {
      case options
      case useVirtual
    }
    
    static let configuration = CommandConfiguration(
      abstract: "Simple program to test the SDL controller routines"
    )
    
    @OptionGroup var options: Options
    
    @Flag(name: [.customLong("virtual")], help: "Simulate a virtual gamepad.")
    var useVirtual: Bool = false
    
    static let name: String = "SDL Test: Controller"
    
    private var renderer: (any Renderer)!
    private var textures: [String : any Texture] = [:]
    private var scene: GamepadScene<Controller>!
    
    private var gameController: GameController {
      gameControllers.last ?? .invalid
    }
    
    func onInit() throws(SDL_Error) -> any Window {
      print("Applying SDL Hints...")
      SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "1")
      SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_PS4_RUMBLE, "1")
      SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_PS5_RUMBLE, "1")
      SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_STEAM, "1")
      SDL_SetHint(SDL_HINT_JOYSTICK_ROG_CHAKRAM, "1")
      SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1")
      SDL_SetHint(SDL_HINT_JOYSTICK_LINUX_DEADZONES, "1")
      SDL_SetHint(SDL_HINT_RENDER_VSYNC, "1")
      
      /* Enable input debug logging */
      SDL_SetLogPriority(Int32(SDL_LOG_CATEGORY_INPUT.rawValue), SDL_LOG_PRIORITY_DEBUG);

      print("Initializing SDL (v\(SDL_Version()))...")
      try SDL_Init(.video, .joystick)

      print("Calculate the size of the window....")
      let display = try Displays.primary.get()
      let contentScale = (try? display.contentScale.get()) ?? 1
      let screenSize = Layout
        .screenSize(scaledBy: contentScale)
        .to(Sint64.self)
      
      print("Creating window (\(screenSize.x) x \(screenSize.y))....")
      let window = try SDL_CreateWindow(
        with: .windowTitle(Self.name),
        .width(screenSize.x), .height(screenSize.y)
      )
      
      defer { print("Initializing complete!") }
      return window
    }
    
    func onReady(window: any Window) throws(SDL_Error) {
      print("Creating renderer...")
      
      self.renderer = try window.createRenderer(with: (SDL_PROP_RENDERER_VSYNC_NUMBER, 1))
      
      self.scene = try .init(
        game: self,
        renderer: renderer,
        bgColor: .white
      )
    }
    
    func onUpdate(window: any Window, _ delta: Uint64) throws(SDL_Error) {
      SDL_Delay(16)
      try scene.update(at: delta)
      try renderer
        .clear(color: .white)
        .draw(node: scene)
        .draw(into: {
          for label in scene.labels {
            try $0.debug(text: label.text, position: label.position, color: .black)
          }
        })
        .present()
    }
    
    func onEvent(window: any Window, _ event: SDL_Event) throws(SDL_Error) {
      var event = event
      try renderer(SDL_ConvertEventToRenderCoordinates, .some(&event))
      try scene.handle(event)
    }
    
    func onShutdown(window: any Window) throws(SDL_Error) {
      try scene.shutdown()
      renderer = nil
    }
    
    func did(connect gameController: inout GameController) throws(SDL_Error) {
      try gameController.open()
    }
  }
}

extension SDL.Test.Controller {
  final class GamepadScene<Game: SwiftSDL.Game>: BaseScene<any Renderer>, @unchecked Sendable {
    required init(game: Game, renderer: any Renderer, bgColor color: SDL_Color) throws (SDL_Error) {
      let size = try renderer.outputSize(as: Float.self)
      super.init(size: size, bgColor: color)
      
      self.game = game
      let textures = [
        "Gamepad (Front)" : try renderer.texture(from: try Load(bitmap: "gamepad_front.bmp"), tag: "Gamepad (Front)"),
        "Gamepad (Back)"  : try renderer.texture(from: try Load(bitmap: "gamepad_back.bmp"), tag: "Gamepad (Back)"),
        "Face (ABXY)"     : try renderer.texture(from: try Load(bitmap: "gamepad_face_abxy.bmp"), tag: "Face (ABXY)"),
        "Face (BAYX)"     : try renderer.texture(from: try Load(bitmap: "gamepad_face_bayx.bmp"), tag: "Face (BAYX)"),
        "Face (Sony)"     : try renderer.texture(from: try Load(bitmap: "gamepad_face_sony.bmp"), tag: "Face (Sony)"),
        "Battery"         : try renderer.texture(from: try Load(bitmap: "gamepad_battery.bmp"), tag: "Battery"),
        "Battery (Wired)" : try renderer.texture(from: try Load(bitmap: "gamepad_battery_wired.bmp"), tag: "Battery (Wired)"),
        "Touchpad"        : try renderer.texture(from: try Load(bitmap: "gamepad_touchpad.bmp"), tag: "Touchpad"),
        "Button"          : try renderer.texture(from: try Load(bitmap: "gamepad_button.bmp"), tag: "Button"),
        "Axis"            : try renderer.texture(from: try Load(bitmap: "gamepad_axis.bmp"), tag: "Axis"),
        "Button (Small)"  : try renderer.texture(from: try Load(bitmap: "gamepad_button_small.bmp"), tag: "Button (Small)"),
        "Axis (Arrow)"    : try renderer.texture(from: try Load(bitmap: "gamepad_axis_arrow.bmp"), tag: "Axis (Arrow)"),
        "Glass"           : try renderer.texture(from: try Load(bitmap: "glass.bmp"), tag: "Glass")
      ]
      
      for (label, texture) in textures {
        let node = try TextureNode(label, with: texture)
        node.isHidden = true
        self.addChild(node)
      }
    }
    
    required init(_ label: String = "") {
      fatalError("init(_:) has not been implemented")
    }
    
    required init(_ label: String = "", size: Size<Float>, bgColor: SDL_Color = .gray, blendMode: SDL_BlendMode = SDL_BLENDMODE_NONE) {
      fatalError("init(_:size:bgColor:blendMode:) has not been implemented")
    }
    
    required init(from decoder: any Decoder) throws {
      fatalError("init(from:) has not been implemented")
    }
    
    private(set) weak var game: Game?

    private var gameController: GameController {
      guard let gameController = game?.gameControllers.last, case(.open) = gameController else {
        return .invalid
      }
      return gameController
    }
    
    private var gameControllerName: String {
      let joystickID = gameController.id
      let isGamepad = gameController.isGamepad
      let isVirtual = gameController.isVirtual
      
      var text = ""
      
      let GetNameFunc = isGamepad ? SDL_GetGamepadNameForID : SDL_GetJoystickNameForID
      if let controllerName = GetNameFunc(joystickID) {
        text = String(cString: controllerName)
      }
      
      text = isVirtual ? "Virtual Controller" : text
      return text
    }
    
    fileprivate var labels: [(text: String, position: Point<Float>)] {
      guard gameController != .invalid else {
        return [
          placeholder
        ]
      }
      var labels = [
        title,
        controllerID,
        gamepadType,
        serial,
        buttonsTitle,
        axisTitle,
        vendorID,
        productID
      ]
      
      labels += gameController.isVirtual ? [subtitle] : []
      
      return labels
    }
    
    private var placeholder: (text: String, position: Point<Float>) {
      let text = "Waiting for gamepad, press A to add a virtual controller"
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, [size.x / 2, 24] - textSize)
    }

    private var title: (text: String, position: Point<Float>) {
      let text = gameControllerName
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, [size.x / 2, 24] - textSize)
    }
    
    private var controllerID: (text: String, position: Point<Float>) {
      let text = "(\(gameController.id))"
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, [size.x - 20, 12] - textSize)
    }
    
    private var subtitle: (text: String, position: Point<Float>) {
      let text = "Click on the gamepad image below to generate input"
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, [size.x / 2, 36] - textSize)
    }
    
    private var gamepadType: (text: String, position: Point<Float>) {
      let text = gameController.isVirtual ? "" : gameController.gamepadType.debugDescription
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, (Layout.typeFrame.lowHalf + Layout.typeFrame.highHalf / 2) - textSize)
    }
    
    /*
    private var steamHandle: (text: String, position: Point<Float>) {
      let text = "Steam: 0x\(String(gameController.gamepadSteamHandle, radix: 16, uppercase: true))"
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, [size.x - 8, size.y - 2] -  textSize)
    }
     */
    
    private var serial: (text: String, position: Point<Float>) {
      let gamepadSerial = gameController.gamepadSerial
      let text = gamepadSerial.isEmpty ? "" : "Serial: \(gamepadSerial)"
      let textSize = text.debugTextSize(as: Float.self) / 2
      return(text, [size.x / 2, size.y - 14] - textSize)
    }
    
    private var buttonsTitle: (text: String, position: Point<Float>) {
      return ("BUTTONS", [
        Layout.panelWidth +
        Layout.panelSpacing +
        Layout.gamepadWidth +
        Layout.panelSpacing + 8,
        Layout.titleHeight + 8
      ])
    }
    
    private var axisTitle: (text: String, position: Point<Float>) {
      return ("AXES", [
        Layout.panelWidth +
        Layout.panelSpacing +
        Layout.gamepadWidth +
        Layout.panelSpacing + 96,
        Layout.titleHeight + 8
      ])
    }
    
    private var vendorID: (text: String, position: Point<Float>) {
      let vID = SDL_GetJoystickVendorForID(gameController.id)
      let text = "VID: 0x".appendingFormat("%.4X", vID)
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, size - textSize - [textSize.x * 3 + 16, 14])
    }
    
    private var productID: (text: String, position: Point<Float>) {
      let pID = SDL_GetJoystickProductForID(gameController.id)
      let text = "PID: 0x".appendingFormat("%.4X", pID)
      let textSize = text.debugTextSize(as: Float.self) / 2
      return (text, size - textSize - [52, 14])
    }

    override func update(at delta: Uint64) throws(SDL_Error) {
      try super.update(at: delta)
      
      let invalidGameController = gameController == .invalid
      
      for child in children {
        switch child.label {
          case "Gamepad (Front)":
            child.isHidden = invalidGameController
            child.position = Layout.gamepadImagePosition
            child.zPosition = -1
          case "Gamepad (Back)":
            child.isHidden = true
            child.position = Layout.gamepadImagePosition
            child.zPosition = -2
          case "Face (ABXY)":
            child.isHidden = invalidGameController || !(gameController.gamepad(labelFor: .south) == .a)
            child.position = Layout.gamepadImagePosition + [363, 118]
          case "Face (BAYX)":
            child.isHidden = invalidGameController || !(gameController.gamepad(labelFor: .south) == .b)
            child.position = Layout.gamepadImagePosition + [363, 118]
          case "Face (Sony)":
            child.isHidden = invalidGameController || !(gameController.gamepad(labelFor: .south) == .cross)
            child.position = Layout.gamepadImagePosition + [363, 118]
          default: ()
        }
      }
    }
    
    override func handle(_ event: SDL_Event) throws(SDL_Error) {
      try super.handle(event)
      
      /*
      if (0x600..<0x800).contains(event.type) {
        for button in gameController.gamepadButtons() {
          print("Button: \(button)", gameController.gamepad(query: button))
        }
        
        for axis in gameController.gamepadAxes() {
          print("Axis: \(axis)", gameController.gamepad(query: axis))
        }
        
        for sensor in gameController.gamepadSensors() {
          gameController.gamepad(activate: sensor)
          print("Sensor Rate: \(sensor)", gameController.gamepad(rate: sensor))
          print("Sensor Data: \(sensor)", gameController.gamepad(query: sensor))
        }
      }
       */
      
      switch event.eventType {
        case .keyDown:
          if event.key.key == SDLK_A {
            try SDL_AttachVirtualJoystick(
              type: .gamepad,
              name: "Virtual Controller",
              touchpads: [.init(nfingers: 1, padding: (0, 0, 0))],
              sensors: [
                .init(type: .accelerometer, rate: 0),
                .init(type: .gyroscope, rate: 0),
              ]
            )
          }
          else if event.key.key == SDLK_D, gameController.isVirtual {
            var gameController = self.gameController
            gameController.close()
          }
        default: ()
      }
    }
  }
}


/*
extension SDL.Test.Controller {
  private func drawButtonColumnUI(
    btnTexture: any Texture,
    joystick: OpaquePointer,
    renderer: any Renderer
  ) throws(SDL_Error) {
    let buttonCount = SDL_GetNumJoystickButtons(joystick)
    for btnIdx in 0..<buttonCount {
      var xPos = buttonsTitle.position.x
      var yPos = buttonsTitle.position.y + (Layout.lineHeight + 2) + ((Layout.lineHeight + 4) * Float(btnIdx))
      let text = "".appendingFormat("%2d:", btnIdx)
      try renderer.debug(text: text, position: [xPos, yPos], color: .black)
      
      xPos += 2 + (Layout.fontCharacterSize * Float(SDL_strlen(text)))
      yPos -= 2
      
      if SDL_GetJoystickButton(joystick, Int32(btnIdx)) {
        try btnTexture.set(colorMod: .init(r: 10, g: 255, b: 21, a: 255))
        try renderer.draw(texture: btnTexture, position: [xPos, yPos])
      }
      else {
        try btnTexture.set(colorMod: .white)
        try renderer.draw(texture: btnTexture, position: [xPos, yPos])
      }
    }
  }
  
  private func drawAxesColumnUI(
    arrowTexture: any Texture,
    joystick: OpaquePointer,
    renderer: any Renderer
  ) throws(SDL_Error) {
    let axisCount = SDL_GetNumJoystickAxes(joystick)
    for axisIdx in 0..<axisCount {
      var xPos = axisTitle.position.x - 8
      var yPos = axisTitle.position.y + (Layout.lineHeight + 2) + ((Layout.lineHeight + 4) * Float(axisIdx))
      let text = "".appendingFormat("%2d:", axisIdx)
      try renderer.debug(text: text, position: [xPos, yPos], color: .black)
      
      /* 'RenderJoystickAxisHighlight' ???
       let pressedColor = SDL_Color(r: 175, g: 238, b: 238, a: 255)
       let highlightColor = SDL_Color(r: 224, g: 255, b: 255, a: 255)
       try renderer.fill(rects: [
       xPos + Layout.fontCharacterSize * Float(SDL_strlen(axisTitle.text)) + 2,
       yPos + Layout.fontCharacterSize / 2,
       100,
       100
       ], color: pressedColor)
       */
      
      xPos += 2 + (Layout.fontCharacterSize * Float(SDL_strlen(text)))
      yPos -= 2
      
      let value = SDL_GetJoystickAxis(joystick, axisIdx)
      
      // Left-Arrow (With Highlight State)
      if value == Int16.min {
        try arrowTexture.set(colorMod: .init(r: 10, g: 255, b: 21, a: 255))
        try renderer.draw(texture: arrowTexture, position: [xPos, yPos])
      }
      else {
        try arrowTexture.set(colorMod: .white)
        try renderer.draw(texture: arrowTexture, position: [xPos, yPos], direction: .horizontal)
      }
      
      // Axis Divider Fill
      let arwSize = try arrowTexture.size(as: Float.self)
      try renderer.fill(rects: [
        xPos + 52,
        yPos,
        4.0,
        arwSize.y
      ], color: .init(r: 200, g: 200, b: 200, a: 255)
      )
      
      // Right-Arrow (With Highlight State)
      if value == Int16.max {
        try arrowTexture.set(colorMod: .init(r: 10, g: 255, b: 21, a: 255))
        try renderer.draw(texture: arrowTexture, position: [xPos + 102, yPos])
      }
      else {
        try arrowTexture.set(colorMod: .white)
        try renderer.draw(texture: arrowTexture, position: [xPos + 102, yPos])
      }
    }
  }
}
 */

/*
final class GamepadNode: TextureNode {
  required init(_ label: String = "Gamepad") {
    super.init(label)
  }
  
  required init(_ label: String = "Gamepad", with texture: any Texture, size: Size<Float>) {
    super.init(label, with: texture, size: size)
  }
  
  required init(from decoder: any Decoder) throws {
    try super.init(from: decoder)
  }
  
  private var joystickID: SDL_JoystickID = .zero
  
  convenience init(id joystickID: SDL_JoystickID, renderer: any Renderer) throws(SDL_Error) {
    self.init("Gamepad")
    self.joystickID = joystickID
    
    self.addChild(
      try TextureNode(
        "Gamepad (Front)",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_front.bmp"),
        renderer: renderer
      )
    )?.zPosition = -1
    
    self.addChild(
      try TextureNode(
        "Gamepad (Back)",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_back.bmp"),
        renderer: renderer
      )
    )?.zPosition = -2
    
    self.addChild(
      try TextureNode(
        "Face (ABXY)",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_face_abxy.bmp"),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Face (BAYX)",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_face_bayx.bmp"),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Face (Sony)",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_face_sony.bmp"),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Battery",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_battery.bmp"),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Battery (Wired)",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_battery_wired.bmp"),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Touchpad",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_touchpad.bmp"),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Button",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_button.bmp"),
        colorMod: .init(r: 10, g: 255, b: 21, a: 255),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Axis",
        position: SDL.Test.Controller.Layout.gamepadImagePosition,
        surface: try Load(bitmap: "gamepad_axis.bmp"),
        colorMod: .init(r: 10, g: 255, b: 21, a: 255),
        renderer: renderer
      )
    )
    
    self.addChild(
      try TextureNode(
        "Button (Small)",
        position: .zero,
        surface: try Load(bitmap: "gamepad_button_small.bmp"),
        renderer: renderer
      )
    )?.zPosition = 6
    
    self.addChild(
      try TextureNode(
        "Axis (Arrow)",
        position: [10, 10],
        surface: try Load(bitmap: "gamepad_axis_arrow.bmp"),
        renderer: renderer
      )
    )?.zPosition = 6
  }
  
  var front: TextureNode { child(matching: "Gamepad (Front)") as! TextureNode }
  var back: TextureNode { child(matching: "Gamepad (Back)") as! TextureNode }
  var btn: TextureNode { child(matching: "Button (Small)") as! TextureNode }
  var arrow: TextureNode { child(matching: "Axis (Arrow)") as! TextureNode }
}
 */

extension SDL.Test.Controller {
  struct Layout {
    static let titleHeight: Float = 48.0
    static let panelSpacing: Float = 25.0
    static let panelWidth: Float = 250.0
    // static let minimumButtonWidth: Float = 96.0
    static let buttonMargin: Float = 16.0
    static let buttonPadding: Float = 12.0
    static let gamepadWidth: Float = 512.0
    static let gamepadHeight: Float = 560.0
    
    static var gamepadImagePosition: Point<Float> {
      [Self.panelWidth + Self.panelSpacing, Self.titleHeight]
    }
    
    static var titleFrame: Rect<Float> {
      let width = gamepadWidth
      let height = String.debugFontSize(as: Float.self) + 2.0 * Self.buttonMargin
      let xPos = Self.panelWidth + Self.panelSpacing
      let yPos = Self.titleHeight / 2 - height / 2
      return Rect(lowHalf: [xPos, yPos], highHalf: [width, height])
    }
    
    static var typeFrame: Rect<Float> {
      let width = Self.panelWidth - 2 * Self.buttonMargin
      let height = String.debugFontSize(as: Float.self) + 2 * Self.buttonMargin
      let xPos = Self.buttonMargin
      let yPos = Self.titleHeight / 2 - height / 2
      return Rect(lowHalf: [xPos, yPos], highHalf: [width, height])
    }
    
    static let sceneWidth = panelWidth
    + panelSpacing
    + gamepadWidth
    + panelSpacing
    + panelWidth
    
    static let sceneHeight = titleHeight
    + gamepadHeight
    
    static func screenSize(scaledBy scale: Float = 1.0) -> Size<Sint64> {
      let scaledSize = Size(x: sceneWidth, y: sceneHeight).to(Float.self) * scale
      let size: Size<Float> = [SDL_ceilf(scaledSize.x), SDL_ceilf(scaledSize.y)]
      return size.to(Sint64.self)
    }
    
    static var touchpadFrame: Rect<Float> {
      [148.0, 20.0, 216.0, 118.0]
    };
  }
}
