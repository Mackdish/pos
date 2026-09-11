export const menu = [
  { id: "F001", name: "Grilled Chicken", price: 650, category: "Mains" }, { id: "F002", name: "Beef Pilau", price: 450, category: "Mains" }, { id: "F003", name: "Chips", price: 180, category: "Sides" }, { id: "F004", name: "Fresh Juice", price: 150, category: "Drinks" }, { id: "F005", name: "Soda", price: 100, category: "Drinks" }, { id: "F006", name: "Chapati", price: 60, category: "Sides" },
];
const seedOrders = [
  { id: "ORD-024", customer: "Walk-in customer", employee: "Jane W.", time: "14:32", date: "Today", items: [{ name: "Grilled Chicken", quantity: 2, price: 650 }, { name: "Chips", quantity: 1, price: 180 }], total: 1480, paymentMethod: "M-Pesa", paymentStatus: "PENDING", orderStatus: "PREPARING" },
  { id: "ORD-023", customer: "Room 12", employee: "Brian K.", time: "13:48", date: "Today", items: [{ name: "Beef Pilau", quantity: 2, price: 450 }, { name: "Fresh Juice", quantity: 2, price: 150 }], total: 1200, paymentMethod: "Cash", paymentStatus: "PAID", orderStatus: "COMPLETED", approvedBy: "Brian K.", approvedAt: "13:48" },
  { id: "ORD-022", customer: "Walk-in customer", employee: "Jane W.", time: "12:15", date: "Today", items: [{ name: "Grilled Chicken", quantity: 1, price: 650 }, { name: "Soda", quantity: 2, price: 100 }], total: 850, paymentMethod: "M-Pesa", paymentStatus: "PAID", orderStatus: "COMPLETED", approvedBy: "Jane W.", approvedAt: "12:18" },
  { id: "ORD-021", customer: "Room 08", employee: "Brian K.", time: "11:06", date: "Today", items: [{ name: "Chips", quantity: 2, price: 180 }, { name: "Chapati", quantity: 2, price: 60 }], total: 480, paymentMethod: "Cash", paymentStatus: "PAID", orderStatus: "COMPLETED", approvedBy: "Brian K.", approvedAt: "11:06" },
];
const key = "kivuHotelOrders";
export function getOrders() { if (typeof window === "undefined") return seedOrders; const stored = window.localStorage.getItem(key); if (!stored) { window.localStorage.setItem(key, JSON.stringify(seedOrders)); return seedOrders; } try { return JSON.parse(stored); } catch { return seedOrders; } }
export function saveOrders(orders) { window.localStorage.setItem(key, JSON.stringify(orders)); }
export function formatMoney(value) { return `KSh ${value.toLocaleString("en-KE")}`; }
