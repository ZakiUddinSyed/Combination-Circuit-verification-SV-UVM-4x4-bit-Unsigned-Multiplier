class transaction;
  randc bit [3:0] a; // Define a random input a
  randc bit [3:0] b; // Define a random input b
  bit [7:0] mul; 	// Define an output mul
  
  function void display(input string tag); // display function to display values of a and b
    $display("[%0s] : a : %0d \t b: %0d \t mul : %0d",tag,a,b,mul); // Display transaction information
  endfunction
  
function transaction copy(); 
  
    copy = new(); // Create a new transaction object
	copy.a = this.a; // Copy the input value
	copy.b = this.b; // Copy the input value
	copy.mul = this.mul; // Copy the output value
endfunction
  
endclass

//////////////////////////////////////////////////

class generator;
transaction tr; // Define a transaction object
  mailbox #(transaction) mbx; // Create a mailbox to send data to the driver
  mailbox #(transaction) mbxref;  // Create a mailbox to send data to the scoreboard for comparison/golden data
event done;    // Event to trigger when the requested number of stimuli is applied
event sconext; // Event to sense the completion of scoreboard work
int count;     // Stimulus count
  
function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
this.mbx = mbx;  // Initialize the mailbox for the driver
    this.mbxref = mbxref; // Initialize the mailbox for the scoreboard
    tr = new(); // Create a new transaction object
endfunction
  
  task run();
    repeat(count) begin
      assert(tr.randomize) else $error("[GEN] : RANDOMIZATION FAILED");
      mbx.put(tr.copy); // Put a copy of the transaction into the driver mailbox
      mbxref.put(tr.copy); // Put a copy of the transaction into the scoreboard mailbox
      tr.display("GEN"); // Display transaction information
      @(sconext); // Wait for the scoreboard's completion signal
    end
    ->done; // Trigger "done" event when all stimuli are applied
  endtask
  
endclass

////////////////////////////////////////////////////

class driver;
  transaction tr; // Define a transaction object
  mailbox #(transaction) mbx; // Create a mailbox to receive data from the generator
  virtual mul_if aif; // Virtual interface for DUT
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx; // Initialize the mailbox for receiving data
  endfunction
  
  task run();
    forever begin
      mbx.get(tr); // Get a transaction from the generator
        aif.a <= tr.a;  // Set DUT input from the transaction
    	aif.b <= tr.b;  // Set DUT input from the transaction
		
        $display("[DRV] : Interface Trigger");  // Display Interface triggered message
        tr.display("DRV"); // Display transaction information
        #20;
    end
  endtask
  
endclass

//////////////////////////////////////////////////////

class monitor;
  transaction tr; // Define a transaction object
  mailbox #(transaction) mbx; // Create a mailbox to send data to the scoreboard
  virtual mul_if aif; // Virtual interface for DUT
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx; // Initialize the mailbox for sending data to the scoreboard
  endfunction
  
  task run();
    tr = new(); // Create a new transaction
    forever begin
      #20;
      tr.a = aif.a;
      tr.b = aif.b;
      tr.mul = aif.mul; // Capture DUT output
      mbx.put(tr); // Send the captured data to the scoreboard
      tr.display("MON"); // Display transaction information
    end
  endtask
  
endclass  

////////////////////////////////////////////////////

class scoreboard;
  transaction tr; // Define a transaction object
  transaction trref; // Define a reference transaction object for comparison
  mailbox #(transaction) mbx; // Create a mailbox to receive data from the driver
  mailbox #(transaction) mbxref; // Create a mailbox to receive reference data from the generator
  event sconext; // Event to signal completion of scoreboard work

  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
    this.mbx = mbx; // Initialize the mailbox for receiving data from the driver
    this.mbxref = mbxref; // Initialize the mailbox for receiving reference data from the generator
  endfunction
  
  task run();
    forever begin
      mbx.get(tr); // Get a transaction from the driver
      mbxref.get(trref); // Get a reference transaction from the generator
      tr.display("SCO"); // Display the driver's transaction information
      trref.display("REF"); // Display the reference transaction information
      if (tr.mul == trref.a * trref.b) // *** input of reference transaction product equals to output of DUT
        $display("[SCO] : DATA MATCHED"); // Compare data and display the result
        else
        $display("[SCO] : DATA MISMATCHED");
      $display("-------------------------------------------------");
      ->sconext; // Signal completion of scoreboard work
    end
  endtask
  
endclass

////////////////////////////////////////////////////////

class environment;
  generator gen; // Generator instance
  driver drv; // Driver instance
  monitor mon; // Monitor instance
  scoreboard sco; // Scoreboard instance
  event next; // Event to signal communication between generator and scoreboard

  mailbox #(transaction) gdmbx; // Mailbox for communication between generator and driver
  mailbox #(transaction) msmbx; // Mailbox for communication between monitor and scoreboard
  mailbox #(transaction) mbxref; // Mailbox for communication between generator and scoreboard
  
  virtual mul_if aif; // Virtual interface for DUT

  function new(virtual mul_if aif);
    gdmbx = new(); // Create a mailbox for generator-driver communication
    mbxref = new(); // Create a mailbox for generator-scoreboard reference data
    gen = new(gdmbx, mbxref); // Initialize the generator
    drv = new(gdmbx); // Initialize the driver
    msmbx = new(); // Create a mailbox for monitor-scoreboard communication
    mon = new(msmbx); // Initialize the monitor
    sco = new(msmbx, mbxref); // Initialize the scoreboard
    this.aif = aif; // Set the virtual interface for DUT
    drv.aif = this.aif; // Connect the virtual interface to the driver
    mon.aif = this.aif; // Connect the virtual interface to the monitor
    gen.sconext = next; // Set the communication event between generator and scoreboard
    sco.sconext = next; // Set the communication event between scoreboard and generator
  endfunction
  /*
  task pre_test();
    drv.reset(); // Perform the driver reset
  endtask
  */
  task test();
    fork
      gen.run(); // Start generator
      drv.run(); // Start driver
      mon.run(); // Start monitor
      sco.run(); // Start scoreboard
    join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered); // Wait for generator to complete
    $finish(); // Finish simulation
  endtask
  
  task run();
    //pre_test(); // Run pre-test setup
    test(); // Run the test
    post_test(); // Run post-test cleanup
  endtask
endclass

/////////////////////////////////////////////////////

module tb;
  
  mul_if aif(); // Create DUT interface

  mult dut(aif.a,aif.b,aif.mul); // Instantiate DUT
  /*
  initial begin
    aif.clk <= 0; // Initialize clock signal
  end
  
  always #10 aif.clk <= ~aif.clk; // Toggle the clock every 10 time units
  */
  environment env; // Create environment instance

  initial begin
    env = new(aif); // Initialize the environment with the DUT interface
    env.gen.count = 30; // Set the generator's stimulus count
    env.run(); // Run the environment
  end
  
  initial begin
    $dumpfile("dump.vcd"); // Specify the VCD dump file
    $dumpvars; // Dump all variables
  end
endmodule

