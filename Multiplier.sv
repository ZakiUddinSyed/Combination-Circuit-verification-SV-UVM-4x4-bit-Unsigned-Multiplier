// Unsigned 4x4 bit Multiplier 
module mult(a, b, mul); // multiplication module
  
input [3:0]    a, b;

output reg [8:0] mul;

always @(*)
begin
   mul <= a * b;
end
endmodule

interface mul_if;
logic [3:0] a;
logic [3:0] b;
logic [8:0] mul;
endinterface






