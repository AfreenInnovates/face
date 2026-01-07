# Setup Guide

```
face/
├── backend/              # Flask backend server
│   ├── app.py
│   └── requirements.txt
└── flutter_app/          # Flutter mobile app
    ├── lib/
    │   └── main.dart
```

## Instructions - this is according to my paths, so ignore path, just run command

- set up virtual env for python first => python -m venv .venv (in one terminal)
    - .venv\Scripts\activate => to activate
    - python -r requirements.txt
- flutter SDK download, and add its `bin` path in environment variables 
    - check whether system or user variables has the 'Path'
    - In that edit, and add new 
    - In that, for me it was : C:\Users\Aynal\flutter\bin
    - So wherever u downloaded the flutter SDK, get the path from there
- and then u should be good to go

till here python and flutter installations must be DONE!!!

### 1. Backend Setup (Terminal 1) (the same terminal where ur .venv is activated)

```bash
cd C:\Users\Aynal\Desktop\Afreen\face\backend
pip install -r requirements.txt
python app.py
```

### 2. Flutter App Setup (Terminal 2) (different terminal)

```bash
cd C:\Users\Aynal\Desktop\Afreen\face\flutter_app
flutter pub get
flutter run
```

for python app.py to run, you must be in backend folder

for flutter to run, you must be in flutter_app folder

in respective terminals

