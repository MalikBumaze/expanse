import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column, Alignment, Row, Border;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/widgets.dart' as pw;

// Local imports
import 'helper/save_file_mobile.dart'
if (dart.library.html) 'helper/save_file_web.dart';
void main() {
  runApp(const CreateExcelWidget());
}
class InvoiceEntry {
  String name;
  double phone;
  double amount;
  String _selectedCurrency;
  DateTime selectedDate;
  List<Transaction> transactions = [];

  InvoiceEntry({
    required this.name,
    required this.phone,
    required this.amount,
    required String currency,
    required this.selectedDate,
  }) : _selectedCurrency = currency,
       transactions = [];

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': phone,
      'price': amount,
      'currency': _selectedCurrency,
      'selectedDate': selectedDate.toIso8601String(),
    };
  }

  factory InvoiceEntry.fromJson(Map<String, dynamic> json) {
    return InvoiceEntry(
      name: json['name'] ?? '',
      phone: (json['amount'] as num?)?.toDouble() ?? 0.0,
      amount: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? '',
      selectedDate: DateTime.parse(json['selectedDate'] ?? ''),
    );
  }

  void addTransaction(Transaction transaction) {
    transactions.add(transaction);
    // Update the amount based on transactions
    amount = _calculateAmountWithTransactions();
  }

  double _calculateAmountWithTransactions() {
    double totalAmount = 0.0;
    for (var transaction in transactions) {
      totalAmount += transaction.type == 'Add' ? transaction.amount : -transaction.amount;
    }
    return totalAmount;
  }
}
class Transaction {
  double amount;
  String type; // 'Add' or 'Deduct'
  DateTime timestamp;
  final String? note;// Added timestamp field

  Transaction({
    required this.amount,
    required this.type,
    required this.timestamp,
    required this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'note': note,// Convert timestamp to string
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      amount: json['amount'].toDouble(),
      type: json['type'],
      timestamp: DateTime.parse(json['timestamp']),
      note: json['note'].toString(),
    );
  }
}
class CreateExcelWidget extends StatelessWidget {
  const CreateExcelWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
          textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
            Theme.of(context).textTheme,
          )
      ),
      home: CreateExcelStatefulWidget(title: 'إكسبانس',),
    );
  }
}
class CreateExcelStatefulWidget extends StatefulWidget {
  const CreateExcelStatefulWidget({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _CreateExcelState createState() => _CreateExcelState();
}
class _CreateExcelState extends State<CreateExcelStatefulWidget> {
  List<InvoiceEntry> invoiceEntries = [];
  List<InvoiceEntry> _filteredEntries = [];
  String _selectedFilterCurrency = '';
  List<Transaction> loadedTransactions = [];
  List<Transaction> _transactionHistory = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _loadTransactionHistory();
  }

  Future<void> _loadEntries() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? entriesJson = prefs.getStringList('invoice_entries');
    if (entriesJson != null) {
      List<InvoiceEntry> entries = entriesJson
          .map((json) => InvoiceEntry.fromJson(jsonDecode(json)))
          .toList();

      // Load transaction history
      List<Transaction> transactionHistory = await _loadTransactionHistory();

      setState(() {
        invoiceEntries = entries;
        _filteredEntries = entries; // Initialize filtered entries
        // Set the loaded transaction history
        _setTransactionHistory(transactionHistory);
      });
    }
  }

  Future<List<Transaction>> _loadTransactionHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? transactionsJson = prefs.getStringList('transaction_history');
    if (transactionsJson != null) {
      List<Transaction> loadedTransactions = transactionsJson
          .map((json) => Transaction.fromJson(jsonDecode(json)))
          .toList();

      print('Transaction history loaded: $loadedTransactions');
      return loadedTransactions;
    }

    return []; // Return an empty list if no transactions are loaded
  }

  void _setTransactionHistory(List<Transaction> transactions) {
    setState(() {
      _transactionHistory = transactions; // Set the loaded transactions
    });
  }


  Future<void> _saveTransactionHistory(List<Transaction> transactions) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> transactionsJson = transactions.map((transaction) => jsonEncode(transaction.toJson())).toList();
      prefs.setStringList('transaction_history', transactionsJson);
      print('Transaction history saved successfully');
    } catch (e) {
      print('Error saving transaction history: $e');
    }
  }

  Future<void> _saveEntries() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> entriesJson = invoiceEntries.map((entry) => jsonEncode(entry.toJson())).toList();
    prefs.setStringList('invoice_entries', entriesJson);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(onPressed:(){_showCurrencyFilterMenu(context);}, icon: Icon(Icons.filter_list)),
          IconButton(
            onPressed: () {
              _showSearchDialog(context);
            },
            icon: Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _filteredEntries.length,
              itemBuilder: (context, index) {
                return _buildEntryCard(_filteredEntries[index], index);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: generateExcel,
                  child: Text('إكسل'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to the screen to add entries
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            AddEntryScreen(onEntryAdded: addEntry),
                      ),
                    );
                  },
                  child: Text('إضافة'),
                ),
              ],

            ),
          ),
          _buildSummaryBox(),
        ],

      ),

    );

  }

  Widget _buildEntryCard(InvoiceEntry entry, int index) {
    Color backgroundColor = entry.amount < 0 ? Colors.red[100]! : Colors.green[100]!;
    if (_selectedFilterCurrency.isNotEmpty && entry._selectedCurrency != _selectedFilterCurrency) {
      return SizedBox.shrink();
    }

    return Dismissible(
      key: Key(entry.name), // Unique key for each entry
      onDismissed: (direction) {
        _deleteEntry(index);
      },
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 16.0),
        child: Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      child: GestureDetector(
        onTap: (){
          _showTransactionDialog(entry, index);
        },
        onLongPress: (){
          _editEntry(entry, index);
        },
        child: Card(
          margin: EdgeInsets.all(8.0),
          elevation: 5.0,
          color: backgroundColor,
          child: ListTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${DateFormat('dd/MM/yy').format(entry.selectedDate)}'),
                Text(entry.name), // Name on the right

              ],
            ),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TransactionHistoryPage(
                          transactions: entry.transactions,
                          invoiceEntryName: entry.name,
                        ),
                      ),
                    );
                  },
                  child: Icon(Icons.history),
                ),
                Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${entry._selectedCurrency}/القيمة: ${entry.amount}'),
                  Text('الحوالات: ${entry.transactions.length}'),
                ],
              ),
                // Amount and Currency at the bottom
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBox() {
    // Calculate total amount, له, and عليه
    double totalAmount = _calculateTotalAmount();
    double negative = _calculateTotalNegativeAmount();
    double positive = _calculateTotalPositiveAmount();

    return Container(
      margin: EdgeInsets.all(16.0),
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المجموع:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '$totalAmount',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'له:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '$negative',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'عليه:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '$positive',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
  void _showTransactionDialog(InvoiceEntry entry, int entryIndex) {
    TextEditingController amountController = TextEditingController();
    TextEditingController noteController = TextEditingController();
    String selectedTransactionType = 'Add';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add Transaction'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: noteController,
                decoration: InputDecoration(labelText: 'Note (Optional)'),
              ),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedTransactionType = 'Add';
                      });
                    },
                    child: Text('Add'),
                  ),
                  SizedBox(width: 8.0),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedTransactionType = 'Deduct';
                      });
                    },
                    child: Text('Deduct'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cancel adding transaction
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Validate input and add transaction to the entry
                final transactionAmount = double.tryParse(amountController.text) ?? 0.0;
                if (transactionAmount != 0) {
                  final transaction = Transaction(
                    timestamp: DateTime.now(),
                    amount: transactionAmount,
                    type: selectedTransactionType,
                    note: noteController.text,
                  );
                  _updateEntryWithTransaction(entry, entryIndex, transaction);
                  Navigator.pop(context); // Close the add transaction dialog
                } else {
                  // Display an error message or handle invalid input
                }
              },
              child: Text('Add Transaction'),
            ),
          ],
        );
      },
    );
  }

  void _updateEntryWithTransaction(InvoiceEntry entry, int entryIndex, Transaction transaction) {
    setState(() {
      if (transaction.type == 'Add') {
        entry.amount += transaction.amount;
      } else if (transaction.type == 'Deduct') {
        entry.amount -= transaction.amount;
      }

      // Add the transaction to the entry's transaction history
      entry.transactions.add(transaction);

      _saveEntries(); // Save entries when adding a transaction
      _saveTransactionHistory(entry.transactions);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransactionHistoryPage(
            transactions: entry.transactions,
            invoiceEntryName: entry.name,
          ),
        ),
      );// Save transaction history
    });
  }

  void _showSearchDialog(BuildContext context) async {
    String query = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text('Search'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                onChanged: (value) {
                  // Handle search query changes
                  // You can filter the list based on the search query here
                  _performSearch(value);
                },
                decoration: InputDecoration(labelText: 'Search'),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );

    if (query.isNotEmpty) {
      // Perform search and update the UI based on the query
      _performSearch(query);
    }
  }

  void _performSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        // If the search query is empty, show all entries without applying the filter
        _filteredEntries = List.from(invoiceEntries);
      } else {
        // Apply both currency filter and search filter by name or phone number
        _filteredEntries = invoiceEntries
            .where((entry) =>
        entry._selectedCurrency == _selectedFilterCurrency ||
            (entry.name.toLowerCase().contains(query.toLowerCase()) ||
                entry.phone.toString().contains(query.toLowerCase())))
            .toList();
      }
    });
  }

  void _showCurrencyFilterMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          child: Wrap(
            children: <Widget>[
              ListTile(
                title: Text('All Currencies'),
                onTap: () {
                  _applyCurrencyFilter('');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('USD'),
                onTap: () {
                  _applyCurrencyFilter('USD');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('LYD'),
                onTap: () {
                  _applyCurrencyFilter('LYD');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text('EUR'),
                onTap: () {
                  _applyCurrencyFilter('EUR');
                  Navigator.pop(context);
                },
              ),
              // Add more currencies as needed
            ],
          ),
        );
      },
    );
  }

  void _applyCurrencyFilter(String selectedCurrency) {
    setState(() {
      _selectedFilterCurrency = selectedCurrency;
    });
  }

  void addEntry(InvoiceEntry entry) {
    // Check if the user already exists
    if (invoiceEntries.any((existingEntry) => existingEntry.name == entry.name)) {
      // Display an error message or handle the case where the user already exists
      // For example, you can show a snackbar with an error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This user already exists.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Add the entry if the user doesn't exist
      setState(() {
        invoiceEntries.add(entry);
        _saveEntries(); // Save entries when adding a new entry
      });
    }
  }

  void _editEntry(InvoiceEntry entry, int index) async {
    InvoiceEntry editedEntry = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return EditEntryDialog(entry: entry);
      },
    );

    setState(() {
      invoiceEntries[index] = editedEntry;
      _saveEntries(); // Save entries when editing an entry
    });
  }

  void _deleteEntry(int index) {
    setState(() {
      invoiceEntries.removeAt(index);
      _saveEntries(); // Save entries when deleting an entry
    });
  }

  Future<void> generateExcel() async {
    List<InvoiceEntry> filteredEntries = _filterEntriesByCurrency(invoiceEntries, _selectedFilterCurrency);

    // Create a new workbook
    final Workbook workbook = Workbook();
    final Worksheet sheet = workbook.worksheets[0];

    // Set column widths and formatting
    _formatColumns(sheet);

    // Set bill-to information
    _setBillToInformation(sheet);

    // Set product details
    _setProductDetails(sheet, filteredEntries);

    // Calculate totals
    _calculateTotals(sheet, filteredEntries);

    // Save and launch the excel.
    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    // Save and launch the file.
    await saveAndLaunchFile(bytes, 'Invoice_${_selectedFilterCurrency}.xlsx');
  }
  List<InvoiceEntry> _filterEntriesByCurrency(List<InvoiceEntry> entries, String currency) {
    if (currency.isEmpty) {
      return entries; // Return all entries if no currency filter is applied
    }

    return entries.where((entry) => entry._selectedCurrency == currency).toList();
  }
  void _formatColumns(Worksheet sheet) {
    // Set column widths
    sheet.getRangeByName('A1').columnWidth = 4.82;
    sheet.getRangeByName('A1:H1').cellStyle.backColor = '#333F4F';
    sheet.getRangeByName('A1:H1').merge();
  }
  void _setBillToInformation(Worksheet sheet) {
    // ... (set bill-to information)
  }
  void _setProductDetails(Worksheet sheet, List<InvoiceEntry> entries) {
    // Loop through invoiceEntries and set product details
    for (int i = 0; i < entries.length; i++) {
      final row = i + 2;
      sheet.getRangeByIndex(row, 2).setText(entries[i].name);
      sheet.getRangeByIndex(row, 3).setNumber(entries[i].phone);
      sheet.getRangeByIndex(row, 4).setNumber(entries[i].amount);
    }
  }
  void _calculateTotals(Worksheet sheet, List<InvoiceEntry> entries) {
    final int startRow = 2;
    final int rowCount = entries.length;
    // Calculate total quantity and total price
    double totalPrice = 0.0;
    for (int i = 0; i < rowCount; i++) {
      final row = startRow + i;

      totalPrice += sheet.getRangeByIndex(row, 4).getNumber();
    }
    // Set total quantity and total price in the last row
    final int totalRow = startRow + rowCount;
    sheet.getRangeByIndex(totalRow, 5).setText('الاجمالي');
    sheet.getRangeByIndex(totalRow, 4).setNumber(totalPrice);
  }
  double _calculateTotalAmount() {
    double totalAmount = 0.0;
    for (var entry in invoiceEntries) {
      totalAmount += entry.amount;
    }
    return totalAmount;
  }
  double _calculateTotalNegativeAmount() {
    double totalNegativeAmount = 0.0;
    for (var entry in invoiceEntries) {
      if (entry.amount < 0) {
        totalNegativeAmount += entry.amount;
      }
    }
    return totalNegativeAmount;
  }
  double _calculateTotalPositiveAmount() {
    double totalPositiveAmount = 0.0;
    for (var entry in invoiceEntries) {
      if (entry.amount > 0) {
        totalPositiveAmount += entry.amount;
      }
    }
    return totalPositiveAmount;
  }
}
class EditEntryDialog extends StatefulWidget {
  final InvoiceEntry entry;
  const EditEntryDialog({Key? key, required this.entry}) : super(key: key);
  @override
  _EditEntryDialogState createState() => _EditEntryDialogState();
}
class _EditEntryDialogState extends State<EditEntryDialog> {
  late TextEditingController productController;
  late TextEditingController quantityController;
  late TextEditingController priceController;
  String _selectedCurrency = 'USD';
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    productController = TextEditingController(text: widget.entry.name);
    quantityController = TextEditingController(text: widget.entry.phone.toString());
    priceController = TextEditingController(text: widget.entry.amount.toString());
    _selectedCurrency = widget.entry._selectedCurrency;

  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Entry'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: productController,
            decoration: InputDecoration(labelText: 'الاسم'),
          ),
          TextField(
            controller: quantityController,
            decoration: InputDecoration(labelText: 'رقم الهاتف'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: priceController,
            decoration: InputDecoration(labelText: 'القيمة'),
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: 16.0),
          DropdownButton<String>(
            value: _selectedCurrency,
            onChanged: (String? newValue) {
              setState(() {
                _selectedCurrency = newValue!;
              });
            },
            items: <String>['USD', 'LYD', 'EUR']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(); // Cancel editing
          },
          child: Text('إلغاء'),
        ),
        TextButton(
          onPressed: () {
            final editedEntry = InvoiceEntry(
              name: productController.text,
              phone: double.tryParse(quantityController.text) ?? 0,
              amount: double.tryParse(priceController.text) ?? 0.0,
              currency: _selectedCurrency,
              selectedDate: _selectedDate,// Set the selected currency
            );
            Navigator.of(context).pop(editedEntry); // Return edited entry
          },
          child: Text('تعديل'),
        ),
      ],
    );
  }
}
class AddEntryScreen extends StatefulWidget {
  final Function(InvoiceEntry) onEntryAdded;
  const AddEntryScreen({Key? key, required this.onEntryAdded}) : super(key: key);
  @override
  _AddEntryScreenState createState() => _AddEntryScreenState();
}
class _AddEntryScreenState extends State<AddEntryScreen> {
  TextEditingController productController = TextEditingController();
  TextEditingController quantityController = TextEditingController();
  TextEditingController priceController = TextEditingController();
  String _selectedCurrency = 'USD';
  DateTime _selectedDate = DateTime.now();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إضافة حساب'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: productController,
              decoration: InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: quantityController,
              decoration: InputDecoration(labelText: 'رقم الهاتف'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: priceController,
              decoration: InputDecoration(labelText: 'القيمة'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      // Make the price value negative
                      double currentPrice = double.tryParse(priceController.text) ?? 0.0;
                      priceController.text = (-currentPrice).toString();
                    });
                  },
                  child: Text('له'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      // Make the price value positive
                      double currentPrice = double.tryParse(priceController.text) ?? 0.0;
                      priceController.text = currentPrice.abs().toString();
                    });
                  },
                  child: Text('عليه'),
                ),
                SizedBox(height: 16.0),
                DropdownButton<String>(
                  value: _selectedCurrency,
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCurrency = newValue!;
                    });
                  },
                  items: <String>['USD', 'LYD', 'EUR']
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ],
            ),
            Column(
              children: [
                SizedBox(height: 50.0),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    // Validate input and add entry to the list
                    final product = productController.text;
                    final quantity = double.tryParse(quantityController.text) ?? 0;
                    final price = double.tryParse(priceController.text) ?? 0.0;
                    if (product.isNotEmpty && quantity > 0 && price != 0) {
                      final entry = InvoiceEntry(name: product, phone: quantity, amount: price, currency: _selectedCurrency, selectedDate: _selectedDate,);
                      widget.onEntryAdded(entry);
                      Navigator.pop(context); // Close the add entry screen
                    } else {
                      // Display an error message or handle invalid input
                    }
                  },
                  child: Text('إضافة', style: TextStyle(color: Colors.white),),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2101),
                    );
                    if (pickedDate != null && pickedDate != _selectedDate) {
                      setState(() {
                        _selectedDate = pickedDate;
                      });
                    }
                  },
                  child: Text('Select Date'),
                ),],
            )
          ],
        ),
      ),
    );
  }
}
class TransactionHistoryPage extends StatefulWidget {
  final String invoiceEntryName;

  TransactionHistoryPage({
    Key? key,
    required this.invoiceEntryName, required List<Transaction> transactions,
  }) : super(key: key);

  @override
  _TransactionHistoryPageState createState() => _TransactionHistoryPageState();
}
class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  late Future<List<Transaction>> _transactionsFuture;
  List<Transaction> transactions = [];

  @override
  void initState() {
    super.initState();
    _transactionsFuture = _loadTransactionHistory();
  }

  Future<List<Transaction>> _loadTransactionHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? transactionsJson = prefs.getStringList('transaction_history');
    if (transactionsJson != null) {
      List<Transaction> loadedTransactions = transactionsJson
          .map((json) => Transaction.fromJson(jsonDecode(json)))
          .toList();
      return loadedTransactions;
    }

    return [];
  }
  @override
  Widget build(BuildContext context) {
    _loadTransactionHistory();
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.invoiceEntryName}'),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf),
            onPressed: () async {
              List<Transaction> transactions = await _transactionsFuture;
              await _exportAsPdf(context, transactions);
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            List<Transaction> transactions = snapshot.data ?? [];
            return _buildTransactionList(transactions);
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  Widget _buildTransactionList(List<Transaction> transactions) {
    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        return _buildTransactionCard(transactions[index]);
      },
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    Color backgroundColor = transaction.type == 'Deduct' ? Colors.red[100]! : Colors.green[100]!;
    String formattedTimestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(transaction.timestamp);
    return Card(
      margin: EdgeInsets.all(8.0),
      elevation: 5.0,
      color: backgroundColor,
      child: ListTile(
        title: Text(formattedTimestamp),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ${transaction.amount}'),
              Text('Note: ${transaction.note}'),
          ],
        ),
        onTap: () {
          // Handle tapping on a transaction, if needed
        },
      ),
    );
  }

  Future<void> _exportAsPdf(BuildContext context, List<Transaction> transactions) async {
    final pdf = pw.Document();
    final arabicFont = pw.Font.ttf(await rootBundle.load("assets/fonts/IBMPlexSansArabic-Regular.ttf"));

    pdf.addPage(pw.MultiPage(
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Text('${widget.invoiceEntryName}', style: pw.TextStyle(font: arabicFont), textDirection: pw.TextDirection.rtl),
        ),
        pw.Table(
          border: pw.TableBorder.all(),
          children: [
            pw.TableRow(
              children: ['Timestamp', 'Amount', 'Note']
                  .map((header) => pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text(header, style: pw.TextStyle(font: arabicFont, fontWeight: pw.FontWeight.bold)),
              ))
                  .toList(),
            ),
            for (var transaction in transactions)
              pw.TableRow(
                children: [
                  pw.Container(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      DateFormat('yyyy-MM-dd HH:mm:ss').format(transaction.timestamp),
                      style: pw.TextStyle(font: arabicFont),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      '${transaction.amount}',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      transaction.note ?? '',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    ));

    // Save the PDF to a temporary file
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/transaction_history.pdf');
    await file.writeAsBytes(await pdf.save());

    // Open the PDF file
    OpenFile.open(file.path);
  }
}
