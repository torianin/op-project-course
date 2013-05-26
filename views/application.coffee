$(document).ready ->
  window.ws = new WebSocket("ws://37.187.40.7:8080") 
  window.ws.onopen = ->
    console.log "connected..."
    name = prompt("Podaj imie:", "Robert")
    window.ws.send name
    $.getJSON "http://torianinmobile.pl/api/map.json", (data) ->
      window.data = data
      window.canvas = new gameCanvas
      window.canvas.draw()
      setInterval () ->
        window.canvas.update()
      , 100
  window.ws.onmessage = (evt) ->
    console.log evt.data
  window.ws.onclose = ->
    console.log "socket closed"

class gameCanvas
  @img
  constructor: (ws)  ->
    @ws = ws
    @c = document.getElementById("game")
    @ctx = @c.getContext("2d")
    @ctx.font = "15px Arial"
    @url = "./img/angel.png"
    @url_rotate = "./img/angel_rotate.png"
    @backgroundurl = "./img/background.png"
  draw: ->
    console.log "dziala"
    @img = new Image()
    @img.src = @url
    @background = new Image()
    @background.src = @backgroundurl
    @ctx.drawImage @background, 0, 0
    for i in [0...window.data.id.length]
      @ctx.fillText window.data.name[i], window.data.coordinates[i][0]+5, window.data.coordinates[i][1]+70
  update: ->
    if window.addEventListener
      addEventListener 'keydown', keydown, yes
    $.getJSON "http://torianinmobile.pl/api/map.json", (data) ->
      window.data = data
    @ctx.drawImage @background, 0, 0
    for i in [0...window.data.id.length]
      @ctx.drawImage @img, window.data.coordinates[i][0], window.data.coordinates[i][1]
      @ctx.fillText window.data.name[i], window.data.coordinates[i][0]+5, window.data.coordinates[i][1]+70
  keydown = (e) ->
    # console.log e.keyCode
    window.ws.send "b" if e.keyCode is (83 or 40) # Down
    window.ws.send "t" if e.keyCode is (87 or 38) # Up
    if e.keyCode is (68 or 39) # Right  
      window.canvas.img.src = window.canvas.url
      window.ws.send "r" 
    if e.keyCode is (65 or 37) # Left
      window.canvas.img.src = window.canvas.url_rotate
      window.ws.send "l" 
