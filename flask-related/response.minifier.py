from flask import Flask
from htmlmin.main import minify

app = Flask('webapp', static_folder='./assets', static_url_path="")



@app.after_request
def minify_response(response):
    """minify html response to decrease site traffic"""
    if response.content_type == u'text/html; charset=utf-8':
        response.set_data(
            minify(
                response.get_data(as_text=True),
                remove_comments=True,
                remove_empty_space=True
            )
        )

        return response
    return response