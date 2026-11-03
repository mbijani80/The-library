import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

const espresso = Color(0xFF17110E), brown = Color(0xFF302019), gold = Color(0xFFC6A15B), cream = Color(0xFFF1E5CF), muted = Color(0xFFB7A58A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.init();
  runApp(const LibraryApp());
}

class LibraryApp extends StatelessWidget {
  const LibraryApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'THE LIBRARY', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: espresso,
      colorScheme: const ColorScheme.dark(primary: gold, secondary: cream, surface: brown),
      appBarTheme: const AppBarTheme(backgroundColor: espresso, foregroundColor: cream, elevation: 0),
      cardTheme: CardThemeData(color: brown, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      useMaterial3: true),
    home: const HomePage());
}

class Store {
  Store._(); static final instance = Store._(); Database? _db;
  Future<void> init() async {
    _db = await openDatabase(p.join(await getDatabasesPath(), 'the_library.db'), version: 1,
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE books(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT,path TEXT,lastPage INTEGER DEFAULT 1,pageCount INTEGER DEFAULT 0,addedAt TEXT)');
        await d.execute('CREATE TABLE quizzes(id INTEGER PRIMARY KEY AUTOINCREMENT,bookId INTEGER,page INTEGER,payload TEXT,completed INTEGER DEFAULT 0,completedAt TEXT,UNIQUE(bookId,page))');
      });
  }
  Database get db => _db!;
  Future<List<Map<String,dynamic>>> books() => db.query('books',orderBy:'addedAt DESC');
  Future<int> addBook(String title,String path) => db.insert('books',{'title':title,'path':path,'lastPage':1,'pageCount':0,'addedAt':DateTime.now().toIso8601String()});
  Future<void> updatePage(int id,int page,int count) => db.update('books',{'lastPage':page,'pageCount':count},where:'id=?',whereArgs:[id]);
  Future<Map<String,dynamic>?> getQuiz(int id,int page) async { final r=await db.query('quizzes',where:'bookId=? AND page=?',whereArgs:[id,page],limit:1); return r.isEmpty?null:r.first; }
  Future<void> saveQuiz(int id,int page,Map<String,dynamic> q) => db.insert('quizzes',{'bookId':id,'page':page,'payload':jsonEncode(q)},conflictAlgorithm:ConflictAlgorithm.replace);
  Future<void> finishQuiz(int id) => db.update('quizzes',{'completed':1,'completedAt':DateTime.now().toIso8601String()},where:'id=?',whereArgs:[id]);
  Future<int> completedToday() async { final day=DateTime.now().toIso8601String().substring(0,10); final r=await db.rawQuery("SELECT COUNT(*) c FROM quizzes WHERE completed=1 AND substr(completedAt,1,10)=?",[day]); return (r.first['c'] as int?)??0; }
  Future<int> total() async { final r=await db.rawQuery('SELECT COUNT(*) c FROM quizzes WHERE completed=1'); return (r.first['c'] as int?)??0; }
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  List<Map<String,dynamic>> books=[]; int today=0,total=0,xp=0; bool loading=true;
  @override void initState(){super.initState();refresh();}
  Future<void> refresh() async { final prefs=await SharedPreferences.getInstance(); final b=await Store.instance.books(); final t=await Store.instance.completedToday(); final n=await Store.instance.total(); if(!mounted)return; setState((){books=b;today=t;total=n;xp=prefs.getInt('xp')??n*10;loading=false;}); }
  Future<void> addPdf() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf']);
    if(r==null||r.files.single.path==null)return;
    final f=r.files.single; final id=await Store.instance.addBook(f.name.replaceAll(RegExp(r'\.pdf$',caseSensitive:false),''),f.path!);
    await refresh(); final b=(await Store.instance.books()).firstWhere((e)=>e['id']==id); if(mounted)openBook(b);
  }
  Future<void> openBook(Map<String,dynamic> b) async { await Navigator.push(context,MaterialPageRoute(builder:(_)=>ReaderPage(book:b))); refresh(); }
  Widget stat(String label,String value,IconData icon)=>Expanded(child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:brown,borderRadius:BorderRadius.circular(14)),child:Column(children:[Icon(icon,color:gold),const SizedBox(height:5),Text(value,style:const TextStyle(color:cream,fontWeight:FontWeight.bold)),Text(label,style:const TextStyle(color:muted,fontSize:9))])));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('THE LIBRARY',style:TextStyle(letterSpacing:3,fontWeight:FontWeight.bold))),
    floatingActionButton:FloatingActionButton.extended(backgroundColor:gold,foregroundColor:espresso,onPressed:addPdf,icon:const Icon(Icons.add),label:const Text('IMPORT PDF')),
    body:loading?const Center(child:CircularProgressIndicator(color:gold)):RefreshIndicator(color:gold,onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(18),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[brown,Color(0xFF49301F)]),borderRadius:BorderRadius.circular(20),border:Border.all(color:gold.withOpacity(.4))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('YOUR DAILY SCHOLARSHIP',style:TextStyle(color:gold,letterSpacing:2,fontSize:11)),
        const SizedBox(height:12),Text(today.toString()+' / 60 pages',style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold,color:cream)),
        const SizedBox(height:10),LinearProgressIndicator(value:(today/60).clamp(0,1),color:gold,backgroundColor:espresso,minHeight:8),
        const SizedBox(height:8),Text((60-today).clamp(0,60).toString()+' pages remaining',style:const TextStyle(color:muted))])),
      const SizedBox(height:14),Row(children:[stat('LEVEL',((xp~/250)+1).toString(),Icons.auto_awesome),const SizedBox(width:8),stat('XP',xp.toString(),Icons.stars),const SizedBox(width:8),stat('PAGES',total.toString(),Icons.menu_book)]),
      const SizedBox(height:24),const Text('YOUR COLLECTION',style:TextStyle(color:cream,letterSpacing:2,fontWeight:FontWeight.bold)),const SizedBox(height:8),
      if(books.isEmpty) Container(padding:const EdgeInsets.all(26),decoration:BoxDecoration(color:brown,borderRadius:BorderRadius.circular(16)),child:const Column(children:[Icon(Icons.local_library_outlined,size:44,color:gold),SizedBox(height:12),Text('Your shelves are waiting.',style:TextStyle(color:cream,fontSize:17)),SizedBox(height:6),Text('Import a PDF to begin.',style:TextStyle(color:muted))])),
      ...books.map((b)=>Card(child:ListTile(leading:const Icon(Icons.menu_book,color:gold,size:30),title:Text(b['title'],style:const TextStyle(color:cream)),subtitle:Text('Last page: '+b['lastPage'].toString(),style:const TextStyle(color:muted)),trailing:const Icon(Icons.chevron_right,color:gold),onTap:()=>openBook(b)))),
      const SizedBox(height:16),const Text('A page counts after all three questions are answered. There is no minimum score.',style:TextStyle(color:muted,height:1.5))
    ])));
}

class ReaderPage extends StatefulWidget { final Map<String,dynamic> book; const ReaderPage({super.key,required this.book}); @override State<ReaderPage> createState()=>_ReaderPageState(); }
class _ReaderPageState extends State<ReaderPage> {
  late final PdfViewerController controller; int page=1,pages=0; bool preparing=false;
  @override void initState(){super.initState();controller=PdfViewerController();page=widget.book['lastPage']??1;}
  Future<String> extract(int n) async { final doc=PdfDocument(inputBytes:await File(widget.book['path']).readAsBytes()); try{return PdfTextExtractor(doc).extractText(startPageIndex:n-1,endPageIndex:n-1);}finally{doc.dispose();} }
  Future<void> changed(int n) async { setState(()=>page=n); await Store.instance.updatePage(widget.book['id'],n,pages); await prepareQuiz(n); }
  Future<void> prepareQuiz(int n) async {
    if(preparing)return; final old=await Store.instance.getQuiz(widget.book['id'],n);
    if(old!=null){final payload=jsonDecode(old['payload']); if((old['completed'] as int)==0 && mounted) await showQuiz(old['id'],payload,n); return;}
    setState(()=>preparing=true);
    try { final text=await extract(n); final quiz=QuizMaker.make(text,n,widget.book['title']); await Store.instance.saveQuiz(widget.book['id'],n,quiz); final row=await Store.instance.getQuiz(widget.book['id'],n); if(mounted)await showQuiz(row!['id'],quiz,n); }
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Question preparation failed: '+e.toString())));}
    finally{if(mounted)setState(()=>preparing=false);}
  }
  Future<void> showQuiz(int id,Map<String,dynamic> q,int n) async { await Navigator.push(context,MaterialPageRoute(builder:(_)=>QuizPage(book:widget.book['title'],page:n,id:id,data:q))); }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.book['title'],maxLines:1,overflow:TextOverflow.ellipsis),actions:[Center(child:Text(page.toString()+(pages>0?' / '+pages.toString():''))),IconButton(onPressed:()=>prepareQuiz(page),icon:const Icon(Icons.quiz,color:gold))]),
    body:Column(children:[Expanded(child:SfPdfViewer.file(File(widget.book['path']),controller:controller,onDocumentLoaded:(d){setState(()=>pages=d.document.pages.count);if(page>1)controller.jumpToPage(page);prepareQuiz(page);},onPageChanged:(d)=>changed(d.newPageNumber))),if(preparing)const LinearProgressIndicator(color:gold),Container(color:brown,padding:const EdgeInsets.all(10),child:const Text('Complete all 3 questions to count this page.',style:TextStyle(color:muted)))]));
}

class QuizMaker {
  static Map<String,dynamic> make(String raw,int page,String title){
    final text=raw.replaceAll(RegExp(r'\s+'),' ').trim(); final parts=text.split(RegExp(r'(?<=[.!?؟])\s+')).where((s)=>s.length>35).toList();
    final source=parts.isEmpty?'متن قابل استخراجی در صفحه '+page.toString()+' از '+title+' پیدا نشد.':parts.first;
    final excerpt=source.length>145?source.substring(0,145)+'…':source;
    final stems=['کدام گزینه با متن این صفحه مطابقت بیشتری دارد؟','کدام عبارت نکته اصلی این بخش را بیان می‌کند؟','برای مرور این صفحه کدام گزاره را باید به خاطر سپرد؟'];
    final wrong=['این عبارت در متن صفحه ذکر نشده است.','این گزینه با محتوای صفحه تطابق ندارد.','این موضوع ارتباط مستقیمی با متن ندارد.'];
    return {'questions':List.generate(3,(i)=>{'question':stems[i],'options':[excerpt,wrong[i],wrong[(i+1)%3],wrong[(i+2)%3]],'answer':0,'explanation':'این پاسخ بر اساس متن استخراج‌شده از صفحه انتخاب شده است: '+excerpt,'chosen':-1})};
  }
}

class QuizPage extends StatefulWidget { final String book; final int page,id; final Map<String,dynamic> data; const QuizPage({super.key,required this.book,required this.page,required this.id,required this.data}); @override State<QuizPage> createState()=>_QuizPageState(); }
class _QuizPageState extends State<QuizPage> {
  late List<Map<String,dynamic>> qs; int index=0; bool done=false;
  @override void initState(){super.initState();qs=List<Map<String,dynamic>>.from((widget.data['questions'] as List).map((e)=>Map<String,dynamic>.from(e)));}
  Future<void> choose(int n) async {setState(()=>qs[index]['chosen']=n);if(index<2){setState(()=>index++);}else{await Store.instance.finishQuiz(widget.id);final prefs=await SharedPreferences.getInstance();await prefs.setInt('xp',(prefs.getInt('xp')??0)+10);setState(()=>done=true);}}
  @override Widget build(BuildContext context){
    if(done){final score=qs.where((q)=>q['chosen']==q['answer']).length;return Scaffold(appBar:AppBar(title:const Text('PAGE COMPLETE')),body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.workspace_premium,color:gold,size:64),const SizedBox(height:16),const Text('A PAGE WELL STUDIED',style:TextStyle(color:gold,letterSpacing:2,fontSize:18)),const SizedBox(height:12),Text(score.toString()+' / 3 correct',style:const TextStyle(color:cream,fontSize:22)),const SizedBox(height:8),const Text('+10 XP • Page added to mission',style:TextStyle(color:muted)),const SizedBox(height:24),ElevatedButton(onPressed:()=>Navigator.pop(context),child:const Text('RETURN TO READING'))])));}
    final q=qs[index]; final opts=q['options'] as List;
    return Scaffold(appBar:AppBar(title:Text('PAGE '+widget.page.toString()+' • QUESTION '+(index+1).toString()+'/3')),body:Directionality(textDirection:TextDirection.rtl,child:ListView(padding:const EdgeInsets.all(20),children:[
      Text(widget.book,style:const TextStyle(color:gold)),const SizedBox(height:20),Text(q['question'],style:const TextStyle(color:cream,fontSize:20,height:1.6,fontWeight:FontWeight.w600)),const SizedBox(height:20),
      ...opts.asMap().entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:10),child:InkWell(onTap:()=>choose(e.key),child:Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:brown,borderRadius:BorderRadius.circular(14),border:Border.all(color:gold.withOpacity(.4))),child:Row(children:[CircleAvatar(radius:14,backgroundColor:gold,child:Text(String.fromCharCode(65+e.key),style:const TextStyle(color:espresso))),const SizedBox(width:12),Expanded(child:Text(e.value,style:const TextStyle(color:cream,height:1.5)))]))))),
      const Text('بدون حداقل نمره؛ فقط به هر سه سؤال پاسخ بده.',style:TextStyle(color:muted))
    ])));
  }
}
