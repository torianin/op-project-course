$(document).ready ->
  
  $("#canvasWrapper").keypress (e) ->
    keys[e.keyCode] = true
    console.log "key pressed!"
   
  ws = new WebSocket("ws://0.0.0.0:8080")

  ws.onmessage = (evt) ->
    console.log evt.data

  ws.onclose = ->
    console.log "socket closed"

  ws.onopen = ->
    console.log "connected..."
    test = prompt("Podaj imie:", "Robert")
    character = new angelCharacter test
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

#Objects
class angelCharacter
  x: 0
  y: 0
  url: "./img/angel.png"
  backgroundurl: "./img/background.png"
  constructor: (@name) ->
    @img = new Image()
    @img.src = @url
    @background = new Image()
    @background.src = @backgroundurl
  update: (ctx) ->
    if @y < 540  then @y = @y + 1 else @y = 0
    @y = @y + 1
    ctx.drawImage @background, 0, 0
    ctx.drawImage @background, 0, 0
    console.log("Updating position: y: #{@y}")
    @draw(ctx)    
  draw: (ctx) ->
    ctx.drawImage @img, @x, @y
    ctx.fillText @name, @x+5, @y+70

