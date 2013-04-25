$(document).ready ->


  ws = new WebSocket("ws://90.156.93.154:8080")

  ws.onmessage = (evt) ->
    console.log evt.data

  ws.onclose = ->
    console.log "socket closed"

  ws.onopen = ->
    console.log "connected..."
    test = prompt("Podaj imie:", "Robert")
    window.character = new angelCharacter test
    if window.addEventListener
      addEventListener 'keydown', doKeyDown, yes
    drawCanvas character
    ws.send test

#Functions
drawCanvas = (angelCharacter) ->
  c = document.getElementById("game")
  ctx = c.getContext("2d")
  ctx.font = "15px Arial"
  angelCharacter.img.onload = ->
    setInterval ( ->
      angelCharacter.update ctx
    ), 30

doKeyDown = (e) ->
  console.log e.keyCode
  window.character.gravity = window.character.gravity + 0.5 if e.keyCode is (83 or 40) # Down
  window.character.gravity = window.character.gravity - 1 if e.keyCode is (87 or 38) # Up
  window.character.speed = window.character.speed + 0.5 if e.keyCode is (68 or 39) # Right  
  window.character.speed = window.character.speed - 0.5 if e.keyCode is (65 or 37) # Left

#Objects
class angelCharacter
  speed: 0
  gravity: 0 
  x: 0
  y: 0
  url: "./img/angel.png"
  url_rotate: "./img/angel_rotate.png"
  backgroundurl: "./img/background.png"
  constructor: (@name) ->
    @img = new Image()
    @img.src = @url
    @background = new Image()
    @background.src = @backgroundurl
  update: (ctx) ->
    if @y < 540  then @y = @y + 1 else @y = 0
    @gravity = @gravity + 0.01
    @x = @x + @speed
    @y = @y + @gravity
    ctx.drawImage @background, 0, 0
    ctx.drawImage @background, 0, 0
    @draw(ctx)    
  draw: (ctx) ->
    @img.src = @url_rotate if @speed < 0
    @img.src = @url if @speed > 0
    ctx.drawImage @img, @x, @y
    ctx.fillText @name, @x+5, @y+70


