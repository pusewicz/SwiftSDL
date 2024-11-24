open class TextureNode: SceneNode, RenderNode {
  internal var _size: Size<Float> = .zero
  
  public var direction: SDL_FlipMode = .none
  public private(set) var texture: (any Texture)!
  public var colorMod: SDL_Color = .white
  
  public required init(_ label: String = "", with texture: any Texture, size: Size<Float>) {
    super.init(label)
    self.texture = texture
    self._size = size
  }

  public convenience init(_ label: String = "", position: Point<Float> = .zero, with texture: any Texture) throws(SDL_Error) {
    self.init(label, with: texture, size: try texture.size(as: Float.self))
    self.position = position
  }
  
  public convenience init(_ label: String = "", position: Point<Float> = .zero, surface: any Surface, colorMod color: SDL_Color = .white, renderer: any Renderer) throws(SDL_Error) {
    let texture = try renderer.texture(from: surface, tag: label)
    let size = try texture.size(as: Float.self)
    self.init(label, with: texture, size: size)
    self.position = position
    self.colorMod = color
  }

  public required init(_ label: String = "") {
    super.init(label)
  }
  
  public required init(from decoder: any Decoder) throws {
    try super.init(from: decoder)
  }
  
  open func draw(_ graphics: any Renderer) throws(SDL_Error) {
    let colorMod = try texture.colorMod.get()
    try texture.set(colorMod: self.colorMod)
    try graphics.draw(
      texture: texture,
      position: position,
      rotatedBy: rotation.value,
      direction: direction
    )
    try texture.set(colorMod: colorMod)
  }
}
