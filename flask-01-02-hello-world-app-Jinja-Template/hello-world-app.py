from flask import Flask

app = Flask(__name__)



@app.route('/')
def head():
    return("<a href="/second/"><h1>Hello World!</h1></a>")


@app.route('/second/')
def second():
    return("<a href="/third/subthird/"><h2>This is the 2nd page</h2></a>")


@app.route('/third/subthird/')
def third():
    return("<a href="/"><h2>This is the subpage of the third page<h2></a>")

@app.route('/fourth/<string:id>')
def fourth(id):
    return('ID of this page is {id}')

if __name__ == '__main__' : 
    #app.run(debug=True )
    app.run(port=80,debug=True )
