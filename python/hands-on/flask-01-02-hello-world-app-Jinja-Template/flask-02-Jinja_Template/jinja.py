from flask import Flask, render_template
app = Flask(__name__)
num1=10
num2=20


@app.route('/')
def head(x=num1,y=num2):
    return render_template('index.html', number1=x, number2=y)

@app.route('/sum')
def number(x=num1,y=num2):
    sum = x + y
    return render_template('body.html', num1=x, num2=y, sum=x+y)
    
if __name__ == '__main__':
    app.run(debug=True)