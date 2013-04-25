$(document).ready ->

  
  debug = (str) ->
    $("#debug").append "<p>" + str + "</p>"

  ws = new WebSocket("ws://0.0.0.0:8080")

  ws.onmessage = (evt) ->
    $("#msg").append "<p>" + evt.data + "</p>"

  ws.onclose = ->
    debug "socket closed"

  ws.onopen = ->
    debug "connected..."
    test = prompt("Podaj imie:", "Robert")
    character = new angelCharacter test
    drawCanvas character
    ws.send test

#Functions
drawCanvas = (angelCharacter) ->
  c = document.getElementById("game")
  ctx = c.getContext("2d")
  ctx.font = "30px Arial"
  ctx.fillText(angelCharacter.name,10,50)

#Objects
class angelCharacter
  constructor: (@name) ->
    alert @name
#  @url: "./img/angel.png"

