FROM python:3.8-slim
WORKDIR /app
RUN apt-get update \
&& apt-get install gcc -y \
&& apt-get clean
EXPOSE 5000
COPY requirements*.txt ./
RUN pip install -r requirements.txt
COPY . .
CMD ["gunicorn", "-b", ":5000", "--log-level", "info", "config.wsgi:application", "-t", "150"]