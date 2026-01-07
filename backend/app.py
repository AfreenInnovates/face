from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
from statistics import mode
from keras.models import load_model
import base64
import os
import sys

# Add parent directory to path to import utils
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.datasets import get_labels
from utils.inference import detect_faces, apply_offsets
from utils.preprocessor import preprocess_input
from utils.inference import load_detection_model

app = Flask(__name__)
CORS(app)

# Load models once at startup
detection_model_path = '../trained_models/detection_models/haarcascade_frontalface_default.xml'
emotion_model_path = '../trained_models/emotion_models/fer2013_mini_XCEPTION.102-0.66.hdf5'
emotion_labels = get_labels('fer2013')

face_detection = load_detection_model(detection_model_path)
emotion_classifier = load_model(emotion_model_path, compile=False)
emotion_target_size = emotion_classifier.input_shape[1:3]

frame_window = 10
emotion_offsets = (20, 40)

# Store emotion windows per session
emotion_windows = {}

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})

@app.route('/detect_emotion', methods=['POST'])
def detect_emotion():
    try:
        data = request.json
        image_data = data.get('image')
        session_id = data.get('session_id', 'default')
        
        # Decode base64 image
        image_bytes = base64.b64decode(image_data.split(',')[1])
        nparr = np.frombuffer(image_bytes, np.uint8)
        bgr_image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if bgr_image is None:
            return jsonify({'error': 'Invalid image'}), 400
        
        gray_image = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2GRAY)
        rgb_image = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
        faces = detect_faces(face_detection, gray_image)
        
        results = []
        
        # Initialize emotion window for session if needed
        if session_id not in emotion_windows:
            emotion_windows[session_id] = []
        
        for face_coordinates in faces:
            x1, x2, y1, y2 = apply_offsets(face_coordinates, emotion_offsets)
            gray_face = gray_image[y1:y2, x1:x2]
            
            try:
                gray_face = cv2.resize(gray_face, emotion_target_size)
            except:
                continue
            
            gray_face = preprocess_input(gray_face, True)
            gray_face = np.expand_dims(gray_face, 0)
            gray_face = np.expand_dims(gray_face, -1)
            
            emotion_prediction = emotion_classifier.predict(gray_face, verbose=0)
            emotion_probability = float(np.max(emotion_prediction))
            emotion_label_arg = int(np.argmax(emotion_prediction))
            emotion_text = emotion_labels[emotion_label_arg]
            
            emotion_windows[session_id].append(emotion_text)
            if len(emotion_windows[session_id]) > frame_window:
                emotion_windows[session_id].pop(0)
            
            try:
                emotion_mode = mode(emotion_windows[session_id])
            except:
                emotion_mode = emotion_text
            
            # Get color based on emotion
            if emotion_text == 'angry':
                color = [int(emotion_probability * 255), 0, 0]
            elif emotion_text == 'sad':
                color = [0, 0, int(emotion_probability * 255)]
            elif emotion_text == 'happy':
                color = [int(emotion_probability * 255), int(emotion_probability * 255), 0]
            elif emotion_text == 'surprise':
                color = [0, int(emotion_probability * 255), int(emotion_probability * 255)]
            else:
                color = [0, int(emotion_probability * 255), 0]
            
            x, y, w, h = face_coordinates
            results.append({
                'emotion': emotion_mode,
                'probability': emotion_probability,
                'bbox': {'x': int(x), 'y': int(y), 'w': int(w), 'h': int(h)},
                'color': color
            })
        
        return jsonify({'faces': results})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

