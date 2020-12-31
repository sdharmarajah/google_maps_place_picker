import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker/google_maps_place_picker.dart';
import 'package:google_maps_place_picker/providers/place_provider.dart';
import 'package:google_maps_place_picker/providers/search_provider.dart';
import 'package:google_maps_place_picker/src/components/prediction_tile.dart';
import 'package:google_maps_place_picker/src/components/rounded_frame.dart';
import 'package:google_maps_place_picker/src/controllers/autocomplete_search_controller.dart';
import 'package:google_maps_place_picker/src/models/previous_location.dart';
import 'package:google_maps_place_picker/src/utils/previous_search_list.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:provider/provider.dart';

class AutoCompleteSearch extends StatefulWidget {
  const AutoCompleteSearch(
      {Key key,
      @required this.sessionToken,
      @required this.onPicked,
      @required this.appBarKey,
      this.hintText,
      this.searchingText = "Searching...",
      this.height = 40,
      this.contentPadding = EdgeInsets.zero,
      this.debounceMilliseconds,
      this.onSearchFailed,
      this.searchBarController,
      this.autocompleteOffset,
      this.autocompleteRadius,
      this.autocompleteLanguage,
      this.autocompleteComponents,
      this.autocompleteTypes,
      this.strictbounds,
      this.region,
      this.initialSearchString,
      this.searchForInitialValue,
      this.autocompleteOnTrailingWhitespace})
      : assert(searchBarController != null),
        super(key: key);

  final String sessionToken;
  final String hintText;
  final String searchingText;
  final double height;
  final EdgeInsetsGeometry contentPadding;
  final int debounceMilliseconds;
  final ValueChanged<Prediction> onPicked;
  final ValueChanged<String> onSearchFailed;
  final SearchBarController searchBarController;
  final num autocompleteOffset;
  final num autocompleteRadius;
  final String autocompleteLanguage;
  final List<String> autocompleteTypes;
  final List<Component> autocompleteComponents;
  final bool strictbounds;
  final String region;
  final GlobalKey appBarKey;
  final String initialSearchString;
  final bool searchForInitialValue;
  final bool autocompleteOnTrailingWhitespace;

  @override
  AutoCompleteSearchState createState() => AutoCompleteSearchState();
}

class AutoCompleteSearchState extends State<AutoCompleteSearch> {
  TextEditingController controller = TextEditingController();
  FocusNode focus = FocusNode();
  OverlayEntry overlayEntry;
  SearchProvider provider = SearchProvider();
  List<ListTile> previousSearchItemTiles;
  List<PreviousLocation> locationFinalList = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchString != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.text = widget.initialSearchString;
        if (widget.searchForInitialValue) {
          _onSearchInputChange();
        }
      });
    }
    controller.addListener(_onSearchInputChange);
    focus.addListener(_onFocusChanged);

    widget.searchBarController.attach(this);
  }

  @override
  void dispose() {
    clearOverlay();
    controller.removeListener(_onSearchInputChange);
    controller.dispose();

    focus.removeListener(_onFocusChanged);
    focus.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    buildPreviousResults(PlaceProvider.of(context, listen: false));
    return ChangeNotifierProvider.value(
      value: provider,
      child: RoundedFrame(
        height: widget.height,
        padding: const EdgeInsets.only(right: 10),
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black54
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 8.0,
        child: Row(
          children: <Widget>[
            SizedBox(width: 10),
            Icon(Icons.search),
            SizedBox(width: 10),
            Expanded(child: _buildSearchTextField()),
            _buildTextClearIcon(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTextField() {
    return TextField(
      controller: controller,
      focusNode: focus,
      decoration: InputDecoration(
        hintText: widget.hintText,
        border: InputBorder.none,
        isDense: true,
        contentPadding: widget.contentPadding,
      ),
      onChanged: (value) {
        buildPreviousResults(PlaceProvider.of(context, listen: false));
      },
    );
  }

  Widget _buildTextClearIcon() {
    return Selector<SearchProvider, String>(
        selector: (_, provider) => provider.searchTerm,
        builder: (_, data, __) {
          if (data.length > 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: GestureDetector(
                child: Icon(
                  Icons.clear,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
                onTap: () {
                  clearText();
                },
              ),
            );
          } else {
            return SizedBox(width: 10);
          }
        });
  }

  _onSearchInputChange() {
    if (!mounted) return;
    this.provider.searchTerm = controller.text;

    PlaceProvider provider = PlaceProvider.of(context, listen: false);

    if (controller.text.isEmpty) {
      provider.debounceTimer?.cancel();
      _searchPlace(controller.text);
      return;
    }

    if (controller.text.trim() == this.provider.prevSearchTerm.trim()) {
      provider.debounceTimer?.cancel();
      return;
    }

    if (!widget.autocompleteOnTrailingWhitespace &&
        controller.text.substring(controller.text.length - 1) == " ") {
      provider.debounceTimer?.cancel();
      return;
    }

    if (provider.debounceTimer?.isActive ?? false) {
      provider.debounceTimer.cancel();
    }

    provider.debounceTimer =
        Timer(Duration(milliseconds: widget.debounceMilliseconds), () {
      _searchPlace(controller.text.trim());
    });
  }

  _onFocusChanged() async {
    PlaceProvider provider = PlaceProvider.of(context, listen: false);
    provider.isSearchBarFocused = focus.hasFocus;
    provider.debounceTimer?.cancel();
    provider.placeSearchingState = SearchingState.Idle;
    await buildPreviousResults(provider);
  }

  Future buildPreviousResults(PlaceProvider provider) async {
    if (controller.text.isEmpty || !focus.hasFocus) {
      getSearchHistory();

      await Future.delayed(Duration(milliseconds: 500), () {
        if (locationFinalList != null) {
          previousSearchItemTiles = List.generate(
            locationFinalList.length,
            (index) {
              print('Location Item: ${locationFinalList[index].location}');
              return ListTile(
                leading: Icon(Icons.access_time),
                title: Text(locationFinalList[index].location),
                onTap: () async {
                  resetSearchBar();
                  controller.text = locationFinalList[index].location;
                  provider.placeSearchingState = SearchingState.Searching;

                  final PlacesDetailsResponse response =
                      await provider.places.getDetailsByPlaceId(
                    locationFinalList[index].placeId,
                    sessionToken: provider.sessionToken,
                    language: widget.autocompleteLanguage,
                  );

                  provider.selectedPlace =
                      PickResult.fromPlaceDetailResult(response.result);

                  // Prevents searching again by camera movement.
                  provider.isAutoCompleteSearching = true;

                  GoogleMapController mapController = provider.mapController;
                  if (controller == null) return;

                  await mapController.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(
                            provider.selectedPlace.geometry.location.lat,
                            provider.selectedPlace.geometry.location.lng),
                        zoom: 16,
                      ),
                    ),
                  );

                  provider.placeSearchingState = SearchingState.Idle;
                },
              );
            },
          );
        } else {
          previousSearchItemTiles = [];
        }
      });

      print('Display previous list called');
      print(previousSearchItemTiles.length);
      _displayOverlay(
        ListBody(
          children: previousSearchItemTiles,
        ),
      );
    }
  }

  _searchPlace(String searchTerm) {
    this.provider.prevSearchTerm = searchTerm;

    if (context == null) return;

    _clearOverlay();

    if (searchTerm.length < 1) return;

    _displayOverlay(_buildSearchingOverlay());

    _performAutoCompleteSearch(searchTerm);
  }

  _clearOverlay() {
    if (overlayEntry != null) {
      overlayEntry.remove();
      overlayEntry = null;
    }
  }

  _displayOverlay(Widget overlayChild) {
    _clearOverlay();

    final RenderBox appBarRenderBox =
        widget.appBarKey.currentContext.findRenderObject();
    final screenWidth = MediaQuery.of(context).size.width;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: appBarRenderBox.size.height,
        left: screenWidth * 0.025,
        right: screenWidth * 0.025,
        child: Material(
          elevation: 4.0,
          child: overlayChild,
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  Widget _buildSearchingOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: <Widget>[
          SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 24),
          Expanded(
            child: Text(
              widget.searchingText ?? "Searching...",
              style: TextStyle(fontSize: 16),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPredictionOverlay(List<Prediction> predictions) {
    return ListBody(
      children: [
        // ...previousSearchItemTiles,
        ...predictions
            .map(
              (p) => PredictionTile(
                prediction: p,
                onTap: (selectedPrediction) async {
                  resetSearchBar();

                  var substring1 =
                      p.description.substring(0, p.description.indexOf(','));
                  var substring2 = p.description
                      .substring(substring1.length + 1, p.description.length);
                  var substring3 =
                      substring2.substring(0, substring2.indexOf(','));
                  print('Selected Location: $substring1,$substring3');
                  controller.text = '$substring1,$substring3';

                  var locationTable = PreviousSearchListProvider();
                  await locationTable.open(path: 'location.db');
                  await locationTable.insertLocation(
                    PreviousLocation(
                      location: '$substring1,$substring3',
                      placeId: selectedPrediction.placeId,
                    ),
                  );
                  // await locationTable.close();

                  widget.onPicked(selectedPrediction);
                },
              ),
            )
            .toList(),
      ],
    );
  }

  _performAutoCompleteSearch(String searchTerm) async {
    PlaceProvider provider = PlaceProvider.of(context, listen: false);

    if (searchTerm.isNotEmpty) {
      final PlacesAutocompleteResponse response =
          await provider.places.autocomplete(
        searchTerm,
        sessionToken: widget.sessionToken,
        location: provider.currentPosition == null
            ? null
            : Location(provider.currentPosition.latitude,
                provider.currentPosition.longitude),
        offset: widget.autocompleteOffset,
        radius: widget.autocompleteRadius,
        language: widget.autocompleteLanguage,
        types: widget.autocompleteTypes,
        components: widget.autocompleteComponents,
        strictbounds: widget.strictbounds,
        region: widget.region,
      );

      if (response.errorMessage?.isNotEmpty == true ||
          response.status == "REQUEST_DENIED") {
        print("AutoCompleteSearch Error: " + response.errorMessage);
        if (widget.onSearchFailed != null) {
          widget.onSearchFailed(response.status);
        }
        return;
      }

      _displayOverlay(_buildPredictionOverlay(response.predictions));
    }
  }

  Future<List<PreviousLocation>> getSearchHistory() async {
    var locationTable = PreviousSearchListProvider();
    await locationTable.open(path: 'location.db');

    var locationList = await locationTable.getPreviousSearchItems();
    for (var item in locationList) {
      print(item.location);
      locationFinalList.add(item);
    }
    var tempList = locationFinalList.reversed.toList();
    locationFinalList.clear();
    locationFinalList.addAll(tempList);
    if (locationFinalList.length > 2) {
      locationFinalList.removeRange(2, locationFinalList.length);
    }
    for (var item in locationFinalList) {
      print('LocationFinalListItem: $item.location');
    }
    return locationList;
  }

  clearText() {
    provider.searchTerm = "";
    controller.clear();
  }

  resetSearchBar() {
    // clearText();
    // Added by abd99
    provider.searchTerm = "";
    clearOverlay();
    buildPreviousResults(PlaceProvider.of(context, listen: false));
    focus.unfocus();
  }

  clearOverlay() {
    _clearOverlay();
  }
}
