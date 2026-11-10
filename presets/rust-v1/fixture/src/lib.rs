/// Returns the sum of two values, widened so it cannot overflow.
pub fn sum(a: i32, b: i32) -> i64 {
    i64::from(a) + i64::from(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds() {
        assert_eq!(sum(2, 3), 5);
        assert_eq!(sum(i32::MAX, 1), i64::from(i32::MAX) + 1);
    }
}
