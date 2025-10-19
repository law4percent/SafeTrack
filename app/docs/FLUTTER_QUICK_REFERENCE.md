# 🚀 Flutter Quick Reference for React Native Developers

## ⚡ Quick Start Commands

```bash
# React Native (Expo)          # Flutter
npm install                    flutter pub get
npx expo start                 flutter run
npm run android                flutter run -d android
npm run ios                    flutter run -d ios
```

## 🔧 Hot Reload

**Expo:** Automatic when you save
**Flutter:** Press `r` in terminal while app is running

## 📦 Package Management

### React Native
```json
// package.json
"dependencies": {
  "react-native": "0.72.0",
  "expo": "~49.0.0"
}
```

### Flutter
```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^2.24.2
```

## 🎨 Widget Cheat Sheet

| React Native | Flutter |
|-------------|---------|
| `<View>` | `Container`, `Column`, `Row` |
| `<Text>` | `Text()` |
| `<TextInput>` | `TextField()`, `TextFormField()` |
| `<Button>` | `ElevatedButton()`, `TextButton()` |
| `<Image>` | `Image.asset()`, `Image.network()` |
| `<ScrollView>` | `SingleChildScrollView()` |
| `<FlatList>` | `ListView.builder()` |
| `<TouchableOpacity>` | `GestureDetector()`, `InkWell()` |
| `<ActivityIndicator>` | `CircularProgressIndicator()` |
| `<Switch>` | `Switch()` |
| `<Modal>` | `showDialog()` |

## 📱 Layout

### React Native
```tsx
<View style={{ flexDirection: 'column' }}>
  <View style={{ flexDirection: 'row' }}>
    <Text>Item 1</Text>
    <Text>Item 2</Text>
  </View>
</View>
```

### Flutter
```dart
Column(  // vertical
  children: [
    Row(  // horizontal
      children: [
        Text('Item 1'),
        Text('Item 2'),
      ],
    ),
  ],
)
```

## 🎯 State Management

### React Native
```tsx
const [count, setCount] = useState(0);
const [name, setName] = useState('');

<Button onPress={() => setCount(count + 1)} />
```

### Flutter
```dart
class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  int count = 0;
  String name = '';

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => setState(() => count++),
      child: Text('$count'),
    );
  }
}
```

## 🧭 Navigation

### React Native
```tsx
navigation.navigate('Details', { id: 123 });
navigation.goBack();
```

### Flutter
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => DetailsScreen(id: 123),
  ),
);
Navigator.pop(context);
```

## 📝 Forms & Validation

### React Native
```tsx
<TextInput
  value={email}
  onChangeText={setEmail}
  placeholder="Email"
/>
```

### Flutter
```dart
TextFormField(
  controller: _emailController,
  decoration: InputDecoration(labelText: 'Email'),
  validator: (value) {
    if (value?.isEmpty ?? true) {
      return 'Please enter email';
    }
    return null;
  },
)
```

## 🎨 Styling

### React Native
```tsx
const styles = StyleSheet.create({
  container: {
    padding: 20,
    backgroundColor: '#fff',
    borderRadius: 10,
  }
});

<View style={styles.container} />
```

### Flutter
```dart
Container(
  padding: EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
  ),
)
```

## 🔥 Firebase

### React Native
```tsx
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';

const auth = getAuth();
await signInWithEmailAndPassword(auth, email, password);
```

### Flutter
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

await Firebase.initializeApp();
final auth = FirebaseAuth.instance;
await auth.signInWithEmailAndPassword(email: email, password: password);
```

## 🔄 Async Operations

### React Native
```tsx
const fetchData = async () => {
  try {
    const response = await fetch(url);
    const data = await response.json();
    setData(data);
  } catch (error) {
    console.error(error);
  }
};

useEffect(() => {
  fetchData();
}, []);
```

### Flutter
```dart
Future<void> fetchData() async {
  try {
    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);
    setState(() => _data = data);
  } catch (e) {
    debugPrint('Error: $e');
  }
}

@override
void initState() {
  super.initState();
  fetchData();
}
```

## 🎭 Conditional Rendering

### React Native
```tsx
{isLoading && <ActivityIndicator />}
{!isLoading && <Text>Content</Text>}

{user ? <Dashboard /> : <Login />}
```

### Flutter
```dart
if (isLoading)
  CircularProgressIndicator()
else
  Text('Content')

user != null ? Dashboard() : Login()
```

## 📋 Lists

### React Native
```tsx
<FlatList
  data={items}
  renderItem={({ item }) => <Text>{item.name}</Text>}
  keyExtractor={(item) => item.id}
/>
```

### Flutter
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return Text(items[index].name);
  },
)

// Or map
Column(
  children: items.map((item) => Text(item.name)).toList(),
)
```

## 🎨 Common Widgets

### Container (like View)
```dart
Container(
  width: 100,
  height: 100,
  padding: EdgeInsets.all(10),
  margin: EdgeInsets.symmetric(vertical: 5),
  decoration: BoxDecoration(
    color: Colors.blue,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Text('Hello'),
)
```

### Column (vertical stack)
```dart
Column(
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Item 1'),
    Text('Item 2'),
  ],
)
```

### Row (horizontal stack)
```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text('Left'),
    Text('Right'),
  ],
)
```

## 🐛 Debugging

### React Native
```tsx
console.log('Value:', value);
console.error('Error:', error);
```

### Flutter
```dart
print('Value: $value');
debugPrint('Debug message');
```

## 💡 Tips

1. **Everything is a Widget** - Like React's "everything is a component"
2. **Stateless vs Stateful** - Like functional vs class components
3. **`const` keyword** - Use for performance (like React.memo)
4. **Hot Reload** - Press `r` (not automatic like Expo)
5. **`mounted` check** - Use `if (!mounted) return;` before setState
6. **Controllers** - TextEditingController ≈ controlled inputs
7. **Keys** - Use `Key` like React keys for list items

## 🎯 Common Mistakes

### ❌ Wrong
```dart
Column(
  children: childrenList.map((child) => Text(child)),  // Missing .toList()
)
```

### ✅ Correct
```dart
Column(
  children: childrenList.map((child) => Text(child)).toList(),
)
```

### ❌ Wrong
```dart
setState(() => count++);  // Outside StatefulWidget
```

### ✅ Correct
```dart
// Only use setState inside StatefulWidget's State class
class _MyWidgetState extends State<MyWidget> {
  void increment() {
    setState(() => count++);
  }
}
```

## 🚀 Your SafeTrack App Structure

```
main.dart
  └─ MyApp (MaterialApp)
      └─ AuthWrapper (checks auth state)
          ├─ LoginScreen (if not logged in)
          └─ DashboardScreen (if logged in)
              └─ Bottom Navigation
                  ├─ DashboardHome
                  ├─ LiveTrackingScreen
                  ├─ MyChildrenScreen
                  └─ SettingsScreen
```

## 📚 Learn More

- Official Docs: https://docs.flutter.dev
- Widget Catalog: https://docs.flutter.dev/development/ui/widgets
- Dart Cheatsheet: https://dart.dev/codelabs/dart-cheatsheet

---

**Remember:** If you can build it in React Native, you can build it in Flutter! The concepts are the same, just different syntax. 🎉