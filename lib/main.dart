import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

const apiBase = 'https://ognispb.online/api/mobile/v1/index.php';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HotelChatApp());
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override String toString() => message;
}

class ApiClient {
  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
  ));
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  String? token;

  Future<void> loadToken() async => token = await storage.read(key: 'api_token');

  Options get auth => Options(headers: token == null ? {} : {'Authorization': 'Bearer $token'});

  Future<Map<String, dynamic>> _unwrap(Response response) async {
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['ok'] != true) throw ApiException(data['error']?.toString() ?? 'Ошибка сервера');
    return data;
  }

  Future<Map<String, dynamic>> login(String login, String password) async {
    try {
      final response = await dio.post(apiBase, queryParameters: {'route': 'login'}, data: {
        'login': login, 'password': password, 'device_name': 'HotelChat Android'
      });
      final data = await _unwrap(response);
      token = data['token'] as String;
      await storage.write(key: 'api_token', value: token);
      return Map<String, dynamic>.from(data['user'] as Map);
    } on DioException catch (e) {
      throw ApiException(_error(e));
    }
  }

  Future<Map<String, dynamic>> me() async {
    try {
      return await _unwrap(await dio.get(apiBase, queryParameters: {'route': 'me'}, options: auth));
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<List<ChatItem>> chats({String status='open'}) async {
    try {
      final data = await _unwrap(await dio.get(apiBase,
        queryParameters: {'route': 'chats', 'status': status, 'limit': 100}, options: auth));
      return (data['items'] as List).map((e) => ChatItem.fromJson(Map<String,dynamic>.from(e))).toList();
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<ChatDetails> chat(int id) async {
    try {
      final data = await _unwrap(await dio.get(apiBase,
        queryParameters: {'route': 'chats/$id'}, options: auth));
      return ChatDetails(
        ChatItem.fromJson(Map<String,dynamic>.from(data['chat'])),
        (data['messages'] as List).map((e)=>MessageItem.fromJson(Map<String,dynamic>.from(e))).toList(),
      );
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<List<MessageItem>> messages(int id, int afterId) async {
    try {
      final data = await _unwrap(await dio.get(apiBase,
        queryParameters: {'route':'chats/$id/messages','after_id':afterId}, options: auth));
      return (data['items'] as List).map((e)=>MessageItem.fromJson(Map<String,dynamic>.from(e))).toList();
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<MessageItem> sendMessage(int id, String text, XFile? image) async {
    try {
      final form = FormData.fromMap({
        'body': text,
        if (image != null) 'image': await MultipartFile.fromFile(image.path, filename: image.name),
      });
      final data = await _unwrap(await dio.post(apiBase,
        queryParameters: {'route':'chats/$id/messages'}, data:form, options:auth));
      return MessageItem.fromJson(Map<String,dynamic>.from(data['message']));
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<void> updateStatus(int id, String state, String status) async {
    try {
      await _unwrap(await dio.post(apiBase, queryParameters: {'route':'chats/$id/status'},
        data:{'admin_state':state,'status':status}, options:auth));
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<void> assignToMe(int id) async {
    try {
      await _unwrap(await dio.post(apiBase, queryParameters: {'route':'chats/$id/assign'},
        data:{}, options:auth));
    } on DioException catch (e) { throw ApiException(_error(e)); }
  }

  Future<List<QuickReply>> quickReplies() async {
    try {
      final data=await _unwrap(await dio.get(apiBase,
        queryParameters:{'route':'quick-replies'},options:auth));
      return (data['items'] as List).map((e)=>QuickReply.fromJson(Map<String,dynamic>.from(e))).toList();
    } on DioException catch(e){ throw ApiException(_error(e)); }
  }

  Future<void> logout() async {
    try {
      if(token!=null) await dio.post(apiBase,queryParameters:{'route':'logout'},options:auth);
    } catch (_) {}
    token=null; await storage.delete(key:'api_token');
  }

  String _error(DioException e) {
    final d=e.response?.data;
    if(d is Map && d['error']!=null) return d['error'].toString();
    if(e.type==DioExceptionType.connectionTimeout || e.type==DioExceptionType.receiveTimeout) {
      return 'Сервер не ответил вовремя';
    }
    return 'Не удалось связаться с сервером';
  }
}

class ChatItem {
  final int id, unread;
  final String roomNumber, roomName, guestName, category, adminState, status;
  final String? assignedName, lastMessage, ratingComment;
  final int? rating;
  final DateTime lastActivity;
  ChatItem({required this.id,required this.unread,required this.roomNumber,required this.roomName,
    required this.guestName,required this.category,required this.adminState,required this.status,
    required this.lastActivity,this.assignedName,this.lastMessage,this.rating,this.ratingComment});
  factory ChatItem.fromJson(Map<String,dynamic> j) {
    final room=Map<String,dynamic>.from(j['room'] as Map);
    return ChatItem(id:j['id'] as int,unread:(j['unread']??0) as int,
      roomNumber:room['number'].toString(),roomName:room['name'].toString(),
      guestName:j['guest_name'].toString(),category:j['category'].toString(),
      adminState:j['admin_state'].toString(),status:j['status'].toString(),
      lastActivity:DateTime.tryParse(j['last_activity_at'].toString())??DateTime.now(),
      assignedName:j['assigned_name']?.toString(),lastMessage:j['last_message']?.toString(),
      rating:j['rating'] as int?,ratingComment:j['rating_comment']?.toString());
  }
}

class MessageItem {
  final int id; final String sender; final String? body,imageUrl; final DateTime createdAt;
  MessageItem({required this.id,required this.sender,this.body,this.imageUrl,required this.createdAt});
  factory MessageItem.fromJson(Map<String,dynamic> j)=>MessageItem(
    id:j['id'] as int,sender:j['sender'].toString(),body:j['body']?.toString(),
    imageUrl:j['image_url']?.toString(),createdAt:DateTime.tryParse(j['created_at'].toString())??DateTime.now());
}

class ChatDetails { final ChatItem chat; final List<MessageItem> messages; ChatDetails(this.chat,this.messages); }
class QuickReply {
  final int id; final String title, bodyRu;
  QuickReply(this.id,this.title,this.bodyRu);
  factory QuickReply.fromJson(Map<String,dynamic> j)=>QuickReply(j['id'] as int,j['title'].toString(),j['body_ru'].toString());
}

final api = ApiClient();

class HotelChatApp extends StatefulWidget {
  const HotelChatApp({super.key});
  @override State<HotelChatApp> createState()=>_HotelChatAppState();
}
class _HotelChatAppState extends State<HotelChatApp> {
  bool ready=false,logged=false;
  @override void initState(){super.initState();_boot();}
  Future<void> _boot() async {
    await api.loadToken();
    if(api.token!=null){try{await api.me();logged=true;}catch(_){await api.logout();}}
    if(mounted)setState(()=>ready=true);
  }
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,title:'HotelChat',
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff245fdb)),
      useMaterial3:true,scaffoldBackgroundColor:const Color(0xfff5f7fb)),
    darkTheme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff6d9cff),brightness:Brightness.dark),
      useMaterial3:true),
    home:!ready?const SplashScreen():logged?
      HomeScreen(onLogout:(){setState(()=>logged=false);}):
      LoginScreen(onLogin:(){setState(()=>logged=true);}),
  );
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override Widget build(BuildContext context)=>const Scaffold(body:Center(child:CircularProgressIndicator()));
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onLogin; const LoginScreen({super.key,required this.onLogin});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen>{
  final login=TextEditingController(),password=TextEditingController(); bool loading=false,obscure=true; String? error;
  Future<void> submit() async {
    setState(()=>loading=true); try{await api.login(login.text.trim(),password.text);widget.onLogin();}
    catch(e){setState(()=>error=e.toString());}finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(
    padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),child:Card(
      child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const CircleAvatar(radius:34,child:Icon(Icons.hotel_rounded,size:36)),const SizedBox(height:16),
        Text('HotelChat',textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),
        const SizedBox(height:6),const Text('Вход для сотрудников',textAlign:TextAlign.center),const SizedBox(height:24),
        TextField(controller:login,autofillHints:const[AutofillHints.username],decoration:const InputDecoration(labelText:'Логин',prefixIcon:Icon(Icons.person_outline))),
        const SizedBox(height:14),
        TextField(controller:password,obscureText:obscure,autofillHints:const[AutofillHints.password],
          onSubmitted:(_)=>submit(),decoration:InputDecoration(labelText:'Пароль',prefixIcon:const Icon(Icons.lock_outline),
            suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility:Icons.visibility_off)))),
        if(error!=null)...[const SizedBox(height:12),Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))],
        const SizedBox(height:20),FilledButton.icon(onPressed:loading?null:submit,icon:loading?
          const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.login),
          label:const Padding(padding:EdgeInsets.symmetric(vertical:13),child:Text('Войти'))),
      ])),
    ))))));
}

class HomeScreen extends StatefulWidget {
  final VoidCallback onLogout; const HomeScreen({super.key,required this.onLogout});
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<ChatItem> items=[]; bool loading=true; String selected='open'; Timer? timer; String? error;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);load();timer=Timer.periodic(const Duration(seconds:12),(_)=>load(silent:true));}
  @override void dispose(){timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed)load(silent:true);}
  Future<void> load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => loading = true);
    }

    try {
      final x = await api.chats(status: selected);
      x.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

      if (!mounted) return;
      setState(() {
        items = x;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Обращения'),actions:[
      IconButton(onPressed:load,icon:const Icon(Icons.refresh)),
      PopupMenuButton<String>(onSelected:(v)async{if(v=='logout'){await api.logout();widget.onLogout();}},
        itemBuilder:(_)=>const[PopupMenuItem(value:'logout',child:ListTile(leading:Icon(Icons.logout),title:Text('Выйти')))])
    ]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,8,12,8),child:SegmentedButton<String>(
        segments:const[ButtonSegment(value:'open',label:Text('Активные'),icon:Icon(Icons.chat_bubble_outline)),
          ButtonSegment(value:'closed',label:Text('Закрытые'),icon:Icon(Icons.check_circle_outline))],
        selected:{selected},onSelectionChanged:(v){selected=v.first;load();})),
      if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      Expanded(child:loading?const Center(child:CircularProgressIndicator()):
        RefreshIndicator(onRefresh:load,child:items.isEmpty?
          ListView(children:const[Padding(padding:EdgeInsets.all(40),child:Center(child:Text('Обращений нет')))]):
          ListView.separated(padding:const EdgeInsets.fromLTRB(12,4,12,24),itemCount:items.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(context,index){
              final c=items[index];return Card(child:ListTile(
                contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
                leading:CircleAvatar(child:Text(c.roomNumber)),
                title:Row(children:[Expanded(child:Text(c.roomName,style:const TextStyle(fontWeight:FontWeight.w700))),
                  if(c.unread>0)Badge(label:Text('${c.unread}'))]),
                subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  const SizedBox(height:4),Text(c.lastMessage?.isNotEmpty==true?c.lastMessage!:'Нет текстового сообщения',maxLines:2,overflow:TextOverflow.ellipsis),
                  const SizedBox(height:6),Wrap(spacing:6,children:[Chip(label:Text(categoryName(c.category)),visualDensity:VisualDensity.compact),
                    Chip(label:Text(stateName(c.adminState)),visualDensity:VisualDensity.compact)])
                ]),
                trailing:Text(DateFormat('HH:mm').format(c.lastActivity)),
                onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ChatScreen(chatId:c.id))).then((_)=>load(silent:true)),
              ));})))
    ])
  );
}

class ChatScreen extends StatefulWidget {
  final int chatId; const ChatScreen({super.key,required this.chatId});
  @override State<ChatScreen> createState()=>_ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen>{
  final controller=TextEditingController(),scroll=ScrollController(); ChatDetails? details; bool loading=true,sending=false; Timer? timer; List<QuickReply> replies=[];
  @override void initState(){super.initState();load();api.quickReplies().then((v){if(mounted)setState(()=>replies=v);});timer=Timer.periodic(const Duration(seconds:4),(_)=>poll());}
  @override void dispose(){timer?.cancel();controller.dispose();scroll.dispose();super.dispose();}
  Future<void> load() async {try{details=await api.chat(widget.chatId);if(mounted)setState(()=>loading=false);jump();}catch(e){if(mounted){setState(()=>loading=false);show(e.toString());}}}
  Future<void> poll() async {if(details==null)return;final after=details!.messages.isEmpty?0:details!.messages.last.id;try{final x=await api.messages(widget.chatId,after);if(x.isNotEmpty&&mounted){setState(()=>details!.messages.addAll(x));jump();}}catch(_){}}
  void jump(){WidgetsBinding.instance.addPostFrameCallback((_){if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);});}
  void show(String s){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> send({XFile? image}) async {final text=controller.text.trim();if(text.isEmpty&&image==null)return;setState(()=>sending=true);try{final m=await api.sendMessage(widget.chatId,text,image);controller.clear();setState(()=>details!.messages.add(m));jump();}catch(e){show(e.toString());}finally{if(mounted)setState(()=>sending=false);}}
  Future<void> pick() async {final x=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:82,maxWidth:1920);if(x!=null)await send(image:x);}
  Future<void> state(String adminState,String status)async{try{await api.updateStatus(widget.chatId,adminState,status);await load();}catch(e){show(e.toString());}}
  @override Widget build(BuildContext context){
    final c=details?.chat;return Scaffold(
      appBar:AppBar(title:Text(c==null?'Чат':'Номер ${c.roomNumber}'),actions:[
        PopupMenuButton<String>(onSelected:(v){if(v=='assign')api.assignToMe(widget.chatId).then((_){show('Обращение назначено вам');load();}).catchError((e){show(e.toString());});
          else if(v=='progress')state('in_progress','open');else if(v=='waiting')state('waiting','open');else if(v=='close')state('done','closed');},
          itemBuilder:(_)=>const[
            PopupMenuItem(value:'assign',child:Text('Назначить на себя')),
            PopupMenuItem(value:'progress',child:Text('В работе')),
            PopupMenuItem(value:'waiting',child:Text('Ожидает')),
            PopupMenuItem(value:'close',child:Text('Закрыть обращение')),
          ])
      ]),
      body:loading?const Center(child:CircularProgressIndicator()):Column(children:[
        if(c!=null)Container(width:double.infinity,padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
          color:Theme.of(context).colorScheme.surfaceContainerHighest,
          child:Text('${categoryName(c.category)} · ${stateName(c.adminState)}${c.assignedName==null?'':' · ${c.assignedName}'}')),
        Expanded(child:ListView.builder(controller:scroll,padding:const EdgeInsets.all(12),itemCount:details!.messages.length,itemBuilder:(context,i){
          final m=details!.messages[i],mine=m.sender=='admin';return Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,
            child:Container(margin:const EdgeInsets.symmetric(vertical:4),padding:const EdgeInsets.all(10),
              constraints:BoxConstraints(maxWidth:MediaQuery.sizeOf(context).width*.78),
              decoration:BoxDecoration(color:mine?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius:BorderRadius.circular(16)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  if(m.imageUrl!=null)ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.network(m.imageUrl!,fit:BoxFit.cover,
                    errorBuilder:(_,__,___)=>const SizedBox(height:120,child:Center(child:Icon(Icons.broken_image))))),
                  if(m.body?.isNotEmpty==true)...[if(m.imageUrl!=null)const SizedBox(height:8),Text(m.body!)],
                  const SizedBox(height:4),Text(DateFormat('HH:mm').format(m.createdAt),style:Theme.of(context).textTheme.labelSmall)
                ])));
        })),
        if(replies.isNotEmpty)SizedBox(height:46,child:ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
          itemCount:replies.length,separatorBuilder:(_,__)=>const SizedBox(width:6),itemBuilder:(_,i)=>ActionChip(label:Text(replies[i].title),onPressed:()=>controller.text=replies[i].bodyRu))),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(8,6,8,8),child:Row(children:[
          IconButton(onPressed:sending?null:pick,icon:const Icon(Icons.photo_outlined)),
          Expanded(child:TextField(controller:controller,minLines:1,maxLines:5,textCapitalization:TextCapitalization.sentences,
            decoration:const InputDecoration(hintText:'Сообщение',border:OutlineInputBorder()))),
          const SizedBox(width:6),IconButton.filled(onPressed:sending?null:send,icon:sending?
            const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send))
        ])))
      ])
    );
  }
}

String categoryName(String code)=>const{
  'cleaning':'Уборка','linen':'Бельё','towels':'Полотенца','repair':'Поломка',
  'taxi':'Такси','restaurant':'Ресторан','wifi':'Wi‑Fi','other':'Другое'
}[code]??code;
String stateName(String code)=>const{
  'new':'Новое','in_progress':'В работе','waiting':'Ожидает','done':'Выполнено'
}[code]??code;
