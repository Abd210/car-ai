import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(GeminiApp());
}

class GeminiApp extends StatefulWidget {
  @override
  _GeminiAppState createState() => _GeminiAppState();
}

class _GeminiAppState extends State<GeminiApp> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  String _response = '';
  String _errorMessage = ''; // To display potential .env errors

  @override
  void initState() {
    super.initState();
    _loadApiKey(); // Load the API key when the app starts
  }

  Future<void> _loadApiKey() async {
    try {
      String? apiKey = dotenv.env['AIzaSyCAPkwkaVad4RsOlrsOFqVdw0OvKScdkiA'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception("GEMINI_API_KEY not found or empty in .env");
      }
      // If the API key is loaded successfully, no further action needed here.
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading API Key: $e";
      });
    }
  }



  Future<void> _submitQuery() async {

    if (_formKey.currentState!.validate()) {
      setState(() { _response = "Loading..."; });

      final query = _textController.text;

      String apiKey = dotenv.env['GEMINI_API_KEY'] ?? ""; // Provide a fallback

      if (apiKey.isEmpty) { // Check after loading and fallback
         _handleError("API Key not found. Check your .env file.");
         return;
      }


      final apiUrl = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
      );

      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({'prompt': {'text': query}});

      try {
        final response = await http.post(apiUrl, headers: headers, body: body);

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(response.body);

          setState(() {
            _response = jsonResponse['candidates'][0]['content'] ?? "No content returned.  Check logs for details.";
            print("Raw Response: $jsonResponse");
          });

        } else {
          _handleError("API Error ${response.statusCode}: ${response.body}");
        }
      } catch (e) {
        _handleError("Request Error: $e");
      }
    }
  }

  void _handleError(String errorMessage) {
    setState(() {
      _response = errorMessage;
    });
    print("Error: $errorMessage");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(title: const Text('Gemini AI Demo')),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_errorMessage.isNotEmpty) ...[  // Display .env error
                  Text(_errorMessage, style: TextStyle(color: Colors.red)),
                  SizedBox(height: 16),
                ],
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _textController,
                    decoration:
                        const InputDecoration(hintText: 'Enter your query'),
                    validator: (value) {
                      return (value == null || value.isEmpty)
                          ? 'Please enter a query'
                          : null;
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: _submitQuery,
                  child: const Text('Submit'),
                ),
                SizedBox(height: 16.0),
                Text(_response),
              ],
            ),
          )),
    );
  }
}