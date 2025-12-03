import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
      
void main() => runApp(const MapPage());
      
  class MapPage extends StatefulWidget {
    const MapPage({super.key});
      
@override
    State<MapPage> createState() => _MyAppState();
      }
      
      class _MyAppState extends State<MapPage> {
        late GoogleMapController mapController;
      
        void _onMapCreated(GoogleMapController controller) {
          mapController = controller;
        }
      
        @override
        Widget build(BuildContext context) {
          return Scaffold(
              appBar: AppBar(
                title: const Text('Nerelerde Görüldü'),
                backgroundColor: Colors.green[700],
              ),
              body: GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: LatLng(39.0, 35.0),
                  zoom: 5,
                ),
              ),
          );
        }
      }
