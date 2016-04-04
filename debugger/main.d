import gtk.Application;

// Windows
import gtk.ApplicationWindow, gtk.Window;
// Menu
import gtk.MenuBar, gtk.MenuItem;
// Input
import gtk.Entry, gtk.Button;
// Display
import gtk.Label, gtk.TextView, gtk.ListBox, gtk.ListBoxRow;
// Layout
import gtk.VBox, gtk.HBox, gtk.Notebook, gtk.Table, gtk.ScrolledWindow;
// Other
import gtk.Widget, gdk.FrameClock, gdk.Event;

import std.conv, std.string;

import common.debugging;
import common.socket;

class ConnectWindow : Window
{
	Entry ipAddressEntry;
	Entry portEntry;

	Debugger debugger;

	this(Debugger debugger)
	{
		super("Connect to Simulator");
		
		this.debugger = debugger;
		this.setBorderWidth(10);

		this.ipAddressEntry = new Entry("127.0.0.1");
		this.portEntry = new Entry("1234");

		auto vbox = new VBox(false, 2);

		auto ipBox = new HBox(false, 2);
		ipBox.packStart(new Label("IP address"), false, false, 5);
		ipBox.packEnd(this.ipAddressEntry, false, false, 5);
		vbox.packStart(ipBox, false, false, 5);

		auto portBox = new HBox(false, 2);
		portBox.packStart(new Label("Port"), false, false, 5);
		portBox.packEnd(this.portEntry, false, false, 5);
		vbox.packStart(portBox, false, false, 5);

		vbox.packEnd(new Button("Connect", &this.onConnectClick), true, true, 5);
		this.add(vbox);

		this.setVisible(false);
	}

	void onConnectClick(Button)
	{
		this.debugger.start(this.ipAddressEntry.getText(), this.portEntry.getText());
		this.setVisible(false);
	}
}

class Debugger : ApplicationWindow
{
	MenuBar menu;
	ConnectWindow connectWindow;
	NonBlockingSocket connection;
	ListBox logView;

	MenuItem connectItem;
	MenuItem disconnectItem;

	Notebook notebook;

	Widget[] coreWidgets;

	this(Application application)
	{
		super(application);
		this.setTitle("Skiron Debugger");
		this.setDefaultSize(640, 480);

		auto vbox = new VBox(false, 0);

		this.menu = new MenuBar();
		this.connectItem = new MenuItem(&this.onConnectClick, "Connect");
		this.menu.append(connectItem);
		this.disconnectItem = new MenuItem(&this.onDisconnectClick, "Disconnect");
		this.menu.append(this.disconnectItem);
		vbox.packStart(this.menu, false, false, 0);

		this.notebook = new Notebook();
		this.notebook.setTabPos(GtkPositionType.TOP);

		this.logView = new ListBox();
		this.notebook.appendPage(this.logView, "Log");
		vbox.packEnd(this.notebook, true, true, 0);

		this.add(vbox);

		this.connectWindow = new ConnectWindow(this);

		this.showAll();

		this.disconnectItem.setVisible(false);

		this.addTickCallback(&this.onTick);
		this.addOnDelete(&this.onDelete);

		this.log("Debugger: Started");
	}

	void onConnectClick(MenuItem)
	{
		this.connectWindow.showAll();
	}

	void onDisconnectClick(MenuItem)
	{
		if (!this.connection.isValid)
		{
			this.log("Emulator: Disconnect failed, no connection");
			return;
		}

		this.connection.shutdown(SocketShutdown.BOTH);
		this.connection.close();

		this.log("Emulator: Disconnected");

		this.connectItem.setVisible(true);
		this.disconnectItem.setVisible(false);

		foreach (widget; this.coreWidgets)
			this.notebook.detachTab(widget);

		this.coreWidgets = [];
	}

	bool onTick(Widget, FrameClock)
	{
		this.handleSocket();

		return true;
	}

	bool onDelete(Event, Widget)
	{
		this.connection.shutdown(SocketShutdown.BOTH);
		this.connection.close();

		return false;
	}

	void start(string ipAddress, string port)
	{
		import std.socket : getAddress;

		this.log("Emulator: Connecting to %s:%s", ipAddress, port);
		auto address = getAddress(ipAddress, port.to!ushort)[0];
		this.connection = NonBlockingSocket(
			AddressFamily.INET, std.socket.SocketType.STREAM, ProtocolType.TCP);

		auto connectionAttempt = this.connection.connect(address);

		this.log("Emulator: Connection successful");
		this.connectItem.setVisible(false);
		this.disconnectItem.setVisible(true);
	}

	void sendMessage(T)(T message)
	{
		ubyte[T.Length] buffer;
		this.connection.send(message.serialize(buffer));
	}

	void handleSocket()
	{
		if (!this.connection.isValid)
			return;

		ushort length;
		auto size = this.connection.receive(length);
		length = length.ntohs();

		if (size == 0)
		{
			this.log("Emulator: Disconnected");
			this.connection = NonBlockingSocket();
		}
		else if (size > 0)
		{
			ubyte[4096] buffer;
			auto readLeft = length;

			while (readLeft)
				readLeft -= this.connection.receive(buffer[(length - readLeft)..length]);

			this.handleMessage(buffer[0..length]);
		}
	}

	void handleMessage(ubyte[] buffer)
	{
		auto messageId = cast(MessageId)buffer[0];

		switch (messageId)
		{
		case MessageId.Initialize:
			auto initialize = Initialize();
			initialize.deserialize(buffer);
			this.log("%s", initialize);

			foreach (core; 0 .. initialize.coreCount)
			{
				auto title = "Core %s".format(core);

				auto label = new Label("Testing 123");
				label.show();

				auto coreGetState = CoreGetState();
				coreGetState.core = core;

				this.sendMessage(coreGetState);

				this.coreWidgets ~= label;
				this.notebook.appendPage(label, title);
			}
			break;
		case MessageId.CoreState:
			auto coreState = CoreState();
			coreState.deserialize(buffer);
			this.log("%s", coreState);
			break;
		default:
			assert(0);
		}
	}

	void log(Args...)(string text, auto ref Args args)
	{
		import std.string, std.datetime;

		auto str = (cast(DateTime)Clock.currTime).toSimpleString();
		str ~= " | ";
		str ~= text.format(args);

		auto label = new Label(str);
		label.setAlignment(0, 0.5f);
		this.logView.insert(label, -1);
		this.logView.showAll();
	}
}

int main(string[] args)
{
	auto application = new Application(null, GApplicationFlags.NON_UNIQUE);
	application.addOnActivate((a) { new Debugger(application); });
	return application.run(args);
}
