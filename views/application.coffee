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
  ctx.font = "30px Arial"
  angelCharacter.img.onload = ->
    ctx.drawImage angelCharacter.img, angelCharacter.x, angelCharacter.y
    ctx.fillText angelCharacter.name, 10, 50

#Objects
class angelCharacter
  x: 0
  y: 0
  url: "./img/angel.png"
  constructor: (@name) ->
    @img = new Image()
    @img.src = @url
  move: ->
    @y += 60

