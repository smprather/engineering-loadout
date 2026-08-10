// Icarus Verilog packaging smoke.
//
// `iverilog -V` prints a version banner from an install whose lib/ivl tree is
// dead or whose vvp.conf still points at the build prefix -- the same silent
// failure ngspice has with a dead datadir. So the smoke compiles and RUNS a
// design and checks the printed value, and the caller additionally executes
// the generated .vvp DIRECTLY so the shebang line (VVP_EXECUTABLE, written
// from lib/ivl/vvp.conf) is exercised rather than bypassed by an explicit
// `vvp` invocation.
//
// Exercises: arithmetic, a synchronous always block, $dumpfile/$dumpvars (the
// VCD writer, i.e. the vvp runtime's VPI system tasks), and $finish.

module smoke;
   reg        clk = 1'b0;
   reg  [7:0] a, b;
   reg  [8:0] acc;
   wire [8:0] sum = a + b;

   always #1 clk = ~clk;

   always @(posedge clk)
     acc <= sum;

   initial begin
      $dumpfile("smoke.vcd");
      $dumpvars(0, smoke);
      a = 8'd17;
      b = 8'd25;
      @(posedge clk);
      @(posedge clk);
      if (sum !== 9'd42) begin
         $display("SMOKE_FAIL sum=%0d expected=42", sum);
         $finish(1);
      end
      if (acc !== 9'd42) begin
         $display("SMOKE_FAIL acc=%0d expected=42 (clocked path)", acc);
         $finish(1);
      end
      $display("SMOKE_OK sum=%0d acc=%0d", sum, acc);
      $finish;
   end
endmodule
